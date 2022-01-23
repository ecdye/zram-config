#!/usr/bin/env bash

if ! [[ -f $2 ]]; then
  curl -s -L "https://downloads.raspberrypi.org/raspios_lite_armhf_latest" -o "$1"
  curl -s "$(curl "https://downloads.raspberrypi.org/raspios_lite_armhf_latest" -s -L -I  -o /dev/null -w '%{url_effective}')".sig -o "${1}.sig"
  gpg -q --keyserver keyserver.ubuntu.com --recv-key 0x8738CD6B956F460C
  gpg -q --trust-model always --verify "${1}.sig" "$1"
  unzip -q "$1" -d .
  qemu-img resize -f raw "$2" 4G
  echo ", +" | sfdisk -N 2 "$2"
fi
loopPrefix="$(kpartx -asv "$2" | grep -oE "loop([0-9]+)" | head -n 1)"
mkdir -p tests/{fs,kernel,dtb}
mount -o rw -t ext4 "/dev/mapper/${loopPrefix}p2" "tests/fs"
mount -o rw -t vfat "/dev/mapper/${loopPrefix}p1" "tests/fs/boot"
rsync -avr --exclude="*.zip" --exclude="*.img" --exclude="*.sig" --exclude="tests/fs" --exclude="tests/dtb" --exclude="tests/kernel" ./ tests/fs/opt/zram
systemd-nspawn --directory="tests/fs" /opt/zram/tests/install-packages.bash
cp tests/fs/boot/kernel* tests/kernel
cp tests/fs/boot/*.dtb tests/dtb
umount tests/fs/boot
umount tests/fs
kpartx -d "$2"
exit 0
