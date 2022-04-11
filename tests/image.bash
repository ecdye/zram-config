#!/usr/bin/env bash

imageFile() {
  local loopPrefix

  if [[ $1 == "mount" ]]; then
    loopPrefix="$(kpartx -asv "$2" | grep -oE "loop([0-9]+)" | head -n 1)"

    mkdir -p tests/{fs,kernel,dtb}
    mount -o rw -t ext4 "/dev/mapper/${loopPrefix}p2" "tests/fs"
    mount -o rw -t vfat "/dev/mapper/${loopPrefix}p1" "tests/fs/boot"
  elif [[ $1 == "umount" ]]; then
    sync
    umount tests/fs/boot
    umount tests/fs
    kpartx -d "$2"
  fi
}

if [[ $1 == "setup" ]]; then
  if ! [[ -f $3 ]]; then
    curl -s -L "https://downloads.raspberrypi.org/raspios_lite_armhf_latest" -o "$2"
    curl -s "$(curl "https://downloads.raspberrypi.org/raspios_lite_armhf_latest" -s -L -I  -o /dev/null -w '%{url_effective}')".sig -o "${2}.sig"
    gpg -q --keyserver keyserver.ubuntu.com --recv-key 0x8738CD6B956F460C
    gpg -q --trust-model always --verify "${2}.sig" "$2"
    xz "$2" -d
  fi
  qemu-img resize -f raw "$3" 4G
  echo ", +" | sfdisk -N 2 "$3"
  imageFile "mount" "$3"
  rsync -avr --exclude="*.zip" --exclude="*.img" --exclude="*.sig" --exclude="tests/fs" --exclude="tests/dtb" --exclude="tests/kernel" ./ tests/fs/opt/zram
  systemd-nspawn --directory="tests/fs" /opt/zram/tests/install-packages.bash
  echo "set enable-bracketed-paste off" >> tests/fs/etc/inputrc  # Prevents weird character output
  # shellcheck disable=SC2016
  echo -n 'test:$6$FdsTan/zaR7eKb8B$mSgk/5q/IFMYOVf2e/NdnUfWBi9clSciE1XD2bHsFNDko0k05zouZkbOPjUeDAYTdkLeWWEwjw5Bow0/le/uv1' > tests/fs/boot/userconf
  cp tests/fs/boot/kernel* tests/kernel
  cp tests/fs/boot/*.dtb tests/dtb
  imageFile "umount" "$3"
elif [[ $1 == "copy-logs" ]]; then
  imageFile "mount" "$2"
  cp tests/fs/opt/zram/logs.tar .
  imageFile "umount" "$2"
fi

exit 0
