#!/bin/sh
set -eu

KERNEL_RELEASE="$(uname -r)"

test -f "/lib/modules/${KERNEL_RELEASE}/modules.dep"
grep -q '/zram\.ko' "/lib/modules/${KERNEL_RELEASE}/modules.dep"
grep -q '/overlay\.ko' "/lib/modules/${KERNEL_RELEASE}/modules.dep"
test -f /etc/zram-config.json
test -f /persistent/test-target/lower.txt

zram-config start

test -d /sys/module/zram
test -d /sys/module/overlay
test -b /dev/zram0
test -b /dev/zram1
grep -q '^/dev/zram0 ' /proc/swaps
grep -q '\[lzo\]' /sys/block/zram0/comp_algorithm
grep -q '/persistent/test-target' /proc/mounts

printf 'written-through-overlay\n' > /persistent/test-target/overlay.txt
sync

zram-config stop

test ! -e /tmp/z-dev-list.json
test ! -e /sys/block/zram0
test ! -e /sys/block/zram1
grep -q '^lower-file$' /persistent/test-target/lower.txt
grep -q '^written-through-overlay$' /persistent/test-target/overlay.txt
