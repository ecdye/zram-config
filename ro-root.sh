#!/bin/sh

#  Read-only Root-FS for Raspian using overlayfs
#  Version 1.1:
#  Changed to use /proc/mounts rathern than /etc/fstab for deriving the root filesystem.
#
#  Version 1:
#  Created 2017 by Pascal Suter @ DALCO AG, Switzerland to work on Raspian as custom init script
#  (raspbian does not use an initramfs on boot)
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see
#    <http://www.gnu.org/licenses/>.
#
#
#  Tested with Raspbian mini, 2017-01-11
#
#  This script will mount the root filesystem read-only and overlay it with a temporary tempfs 
#  which is read-write mounted. This is done using the overlayFS which is part of the linux kernel 
#  since version 3.18. 
#  when this script is in use, all changes made to anywhere in the root filesystem mount will be lost 
#  upon reboot of the system. The SD card will only be accessed as read-only drive, which significantly
#  helps to prolong its life and prevent filesystem coruption in environments where the system is usually
#  not shut down properly 
#
#  Install: 
#  copy this script to /sbin/overlayRoot.sh and add "init=/sbin/overlayRoot.sh" to the cmdline.txt 
#  file in the raspbian image's boot partition. 
#  I strongly recommend to disable swapping before using this. it will work with swap but that just does 
#  not make sens as the swap file will be stored in the tempfs which again resides in the ram.
#  run these commands on the booted raspberry pi BEFORE you set the init=/sbin/overlayRoot.sh boot option:
#  sudo dphys-swapfile swapoff
#  sudo dphys-swapfile uninstall
#  sudo update-rc.d dphys-swapfile remove
#
#  To install software, run upgrades and do other changes to the raspberry setup, simply remove the init= 
#  entry from the cmdline.txt file and reboot, make the changes, add the init= entry and reboot once more. 
 
fail(){
	echo -e "$1"
	/bin/bash
}

createZramDrive () {
	# Check Zram Class created
	modprobe zram

	echo "lz4" > /sys/block/zram0/comp_algorithm
	echo "1000M" > /sys/block/zram0/disksize
	echo "333M" > /sys/block/zram0/mem_limit
	mke2fs -v -t ext4 -s 1024 -L zram-config0 /dev/zram0
	
}

# load module
modprobe overlay
if [ $? -ne 0 ]; then
    fail "ERROR: missing overlay kernel module"
fi
# mount /proc
mount -t proc proc /proc

# create a writable fs to then create our mountpoints 
mount -t tmpfs inittemp /mnt
if [ $? -ne 0 ]; then
    fail "ERROR: could not create a temporary filesystem to mount the base filesystems for overlayfs"
fi
mkdir /mnt/lower
mkdir /mnt/rw

createZramDrive
mount -t ext4 /dev/zram0 /mnt/rw

#mount -t tmpfs root-rw /mnt/rw
if [ $? -ne 0 ]; then
    fail "ERROR: could not create tempfs for upper filesystem"
fi
mkdir /mnt/rw/upper
mkdir /mnt/rw/work
mkdir /mnt/newroot

# mount root filesystem readonly 
rootDev=`awk '$2 == "/" {print $1}' /proc/mounts`
rootMountOpt=`awk '$2 == "/" {print $4}' /proc/mounts`
rootFsType=`awk '$2 == "/" {print $3}' /proc/mounts`
mount -t ${rootFsType} -o ${rootMountOpt},ro ${rootDev} /mnt/lower
if [ $? -ne 0 ]; then
    fail "ERROR: could not ro-mount original root partition"
fi
mount -t overlay -o lowerdir=/mnt/lower,upperdir=/mnt/rw/upper,workdir=/mnt/rw/work overlayfs-root /mnt/newroot
if [ $? -ne 0 ]; then
    fail "ERROR: could not mount overlayFS"
fi
# create mountpoints inside the new root filesystem-overlay
mkdir /mnt/newroot/ro
mkdir /mnt/newroot/rw
# remove root mount from fstab (this is already a non-permanent modification)
grep -v "$rootDev" /mnt/lower/etc/fstab > /mnt/newroot/etc/fstab
echo "#the original root mount has been removed by overlayRoot.sh" >> /mnt/newroot/etc/fstab
echo "#this is only a temporary modification, the original fstab" >> /mnt/newroot/etc/fstab
echo "#stored on the disk can be found in /ro/etc/fstab" >> /mnt/newroot/etc/fstab
# change to the new overlay root
cd /mnt/newroot
pivot_root . mnt
exec chroot . sh -c "$(cat <<END
# move ro and rw mounts to the new root
mount --move /mnt/mnt/lower/ /ro
if [ $? -ne 0 ]; then
    echo "ERROR: could not move ro-root into newroot"
    /bin/bash
fi
mount --move /mnt/mnt/rw /rw
if [ $? -ne 0 ]; then
    echo "ERROR: could not move tempfs rw mount into newroot"
    /bin/bash
fi
# unmount unneeded mounts so we can unmout the old readonly root
umount /mnt/mnt
umount /mnt/proc
umount -l -f /mnt/dev
umount -l -f /mnt
# continue with regular init
exec /sbin/init
END
)"
