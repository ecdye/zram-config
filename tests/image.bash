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
  rsync -avr --exclude="*.img" --exclude="*.sig" --exclude="tests/fs" --exclude="tests/dtb" --exclude="tests/kernel" ./ tests/fs/opt/zram
  systemd-nspawn --directory="tests/fs" /opt/zram/tests/install-packages.bash
  echo "set enable-bracketed-paste off" >> tests/fs/etc/inputrc  # Prevents weird character output
  cp tests/fs/boot/kernel* tests/kernel
  cp tests/fs/boot/*.dtb tests/dtb
  # Compile a customized DTB
  git clone https://github.com/raspberrypi/utils.git
  # Get utilities
  cmake utils/dtmerge
  make
  sudo make install
  cp tests/dtb/bcm2710-rpi-3-b.dtb custom.dtb
  # (dtparam=uart0=on)
  dtmerge custom.dtb merged.dtb - uart0=on
  mv merged.dtb custom.dtb
  # (dtoverlay=disable-bt)
  dtmerge custom.dtb merged.dtb tests/fs/boot/overlays/disable-bt.dtbo
  mv merged.dtb custom.dtb
  imageFile "umount" "$3"
elif [[ $1 == "copy-logs" ]]; then
  imageFile "mount" "$2"
  cp tests/fs/opt/zram/logs.tar .
  imageFile "umount" "$2"
fi

exit 0
