#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${OUT_DIR:-${REPO_ROOT}/.ci-out}"
KERNEL_BUILD="${OUT_DIR}/kernel-build"
QEMU_LOG="${OUT_DIR}/qemu.log"

rm -f "${QEMU_LOG}"

timeout --foreground 10m qemu-system-x86_64 \
    -m 2048 \
    -smp 2 \
    -nographic \
    -no-reboot \
    -monitor none \
    -kernel "${KERNEL_BUILD}/arch/x86/boot/bzImage" \
    -initrd "${OUT_DIR}/initramfs.cpio.gz" \
    -append "console=ttyS0 rdinit=/init" \
    -drive "file=${OUT_DIR}/persist.img,format=raw,if=virtio" | tee "${QEMU_LOG}"

grep -q "TEST_PASS" "${QEMU_LOG}"
