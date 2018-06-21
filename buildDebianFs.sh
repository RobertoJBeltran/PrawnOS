#!/bin/sh -xe

# Build fs, image


KVER=4.9.30

outmnt=$(mktemp -d -p `pwd`)
inmnt=$(mktemp -d -p `pwd`)

outdev=/dev/loop6
indev=/dev/loop7

#A hacky way to ensure the loops are properly unmounted and the temp files are properly deleted.
#Without this, a reboot is required to properly clean the loop devices and ensure a clean build 
cleanuptwice() {
  cleanup
  cleanup

}

cleanup() {
  set +e

  umount -l $inmnt > /dev/null 2>&1
  rmdir $inmnt > /dev/null 2>&1
  losetup -d $indev > /dev/null 2>&1

  umount -l $outmnt > /dev/null 2>&1
  rmdir $outmnt > /dev/null 2>&1
  losetup -d $outdev > /dev/null 2>&1
}

trap cleanuptwice INT TERM EXIT


create_image() {
  # it's a sparse file - that's how we fit a 16GB image inside a 2GB one
  dd if=/dev/zero of=$1 bs=$3 count=$4 conv=sparse
  parted --script $1 mklabel gpt
  cgpt create $1
  cgpt add -i 1 -t kernel -b 8192 -s 65536 -l Kernel -S 1 -T 5 -P 10 $1
  start=$((8192 + 65536))
  end=`cgpt show $1 | grep 'Sec GPT table' | awk '{print $1}'`
  size=$(($end - $start))
  cgpt add -i 2 -t data -b $start -s $size -l Root $1
  # $size is in 512 byte blocks while ext4 uses a block size of 1024 bytes
  losetup -P $2 $1
  mkfs.ext4 -F -b 1024 -m 0 -O ^has_journal ${2}p2 $(($size / 2))

  # mount the / partition
  mount -o noatime ${2}p2 $5
}

# create a 2GB image with the Chrome OS partition layout
create_image debian-stretch-c201-libre-2GB.img $outdev 50M 40 $outmnt

# INCLUDES=apt-utils,libc6,libdebconfclient0,awk,libz2-1.0,libblzma5,libselinux1,tar,libtinfo5,zlib1g,udev,kmod,net-tools,traceroute,iproute2,isc-dhcp-client,wpasupplicant,iw,alsa-utils,cgpt,vim-tiny,less,psmisc,netcat-openbsd,ca-certificates,bzip2,xz-utils,unscd,lightdm,lightdm-gtk-greeter,xfce4,xorg,ifupdown,nano,wicd,wicd-curses

# install Debian on it
qemu-debootstrap --arch=armhf --foreign stretch --variant minbase --include=systemd,systemd-sysv,dbus $outmnt http://deb.debian.org/debian
chroot $outmnt passwd -d root
#echo -n debsus > $outmnt/etc/hostname
#install -D -m 644 80disable-recommends $outmnt/etc/apt/apt.conf.d/80disable-recommends
cp -f /etc/resolv.conf $outmnt/etc/
chroot $outmnt apt update
chroot $outmnt apt install -y udev kmod net-tools inetutils-ping traceroute iproute2 isc-dhcp-client wpasupplicant iw alsa-utils cgpt vim-tiny less psmisc netcat-openbsd ca-certificates bzip2 xz-utils unscd ifupdown nano apt-utils python python-urwid
chroot $outmnt apt-get autoremove --purge
chroot $outmnt apt-get clean
chroot $outmnt apt-get install -d -y wicd-daemon wicd wicd-curses
#sed -i s/^[3-6]/\#\&/g $outmnt/etc/inittab
#sed -i s/'enable-cache            hosts   no'/'enable-cache            hosts   yes'/ -i $outmnt/etc/nscd.conf
rm -f $outmnt/etc/resolv.conf

# put the kernel in the kernel partition, modules in /lib/modules and AR9271
# firmware in /lib/firmware
dd if=linux-$KVER/vmlinux.kpart of=${outdev}p1 conv=notrunc
make -C linux-$KVER ARCH=arm INSTALL_MOD_PATH=$outmnt modules_install
rm -f $outmnt/lib/modules/3.14.0/{build,source}
install -D -m 644 open-ath9k-htc-firmware/target_firmware/htc_9271.fw $outmnt/lib/firmware/htc_9271.fw

# create a 16GB image
create_image debian-stretch-c201-libre-16GB.img $indev 512 30785536 $inmnt

# copy the kernel and / of the 2GB image to the 16GB one
dd if=${outdev}p1 of=${indev}p1 conv=notrunc
cp -a $outmnt/* $inmnt/

umount -l $inmnt
rmdir $inmnt
losetup -d $indev

# move the 16GB image inside the 2GB one
cp -f debian-stretch-c201-libre-16GB.img $outmnt/
echo "DONE!"
cleanup

