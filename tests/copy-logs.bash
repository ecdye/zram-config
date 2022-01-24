#!/usr/bin/env bash

loopPrefix="$(kpartx -asv "$1" | grep -oE "loop([0-9]+)" | head -n 1)"

mount -o rw -t ext4 "/dev/mapper/${loopPrefix}p2" "tests/fs"
cp tests/fs/usr/local/share/zram-config/log/zram-config.log .
umount tests/fs
kpartx -d "$1"
exit 0
