#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${OUT_DIR:-${REPO_ROOT}/.ci-out}"
KERNEL_SUBMODULE_PATH="${KERNEL_SUBMODULE_PATH:-linux}"
KERNEL_SRC="${REPO_ROOT}/${KERNEL_SUBMODULE_PATH}"
KERNEL_BUILD="${OUT_DIR}/kernel-build"
INITRAMFS_ROOT="${OUT_DIR}/initramfs-root"
PERSIST_IMG="${OUT_DIR}/persist.img"
PERSIST_MNT="${OUT_DIR}/persist-mount"
KERNEL_FRAGMENT="${REPO_ROOT}/.github/kernel/github-ci-x86_64.config"
ZIG_TARGET="${ZIG_TARGET:-x86_64-linux-musl}"

copy_binary_with_libs() {
    local src="$1"
    local dest="$2"

    install -Dm755 "$(readlink -f "${src}")" "${INITRAMFS_ROOT}${dest}"

    while read -r lib; do
        [[ -n "${lib}" ]] || continue
        install -Dm755 "${lib}" "${INITRAMFS_ROOT}${lib}"
    done < <(ldd "${src}" 2>/dev/null | awk '
        /=>/ && $3 ~ /^\// { print $3 }
        $1 ~ /^\// { print $1 }
    ' | sort -u || true)
}

if [[ ! -f "${KERNEL_SRC}/Makefile" ]]; then
    printf 'expected a kernel submodule at %s\n' "${KERNEL_SRC}" >&2
    exit 1
fi

mkdir -p "${OUT_DIR}" "${KERNEL_BUILD}" "${INITRAMFS_ROOT}" "${PERSIST_MNT}"

zig build -Doptimize=ReleaseSafe -Dtarget="${ZIG_TARGET}"

make -C "${KERNEL_SRC}" O="${KERNEL_BUILD}" x86_64_defconfig
bash "${KERNEL_SRC}/scripts/kconfig/merge_config.sh" -O "${KERNEL_BUILD}" "${KERNEL_BUILD}/.config" "${KERNEL_FRAGMENT}"
make -C "${KERNEL_SRC}" O="${KERNEL_BUILD}" olddefconfig
make -C "${KERNEL_SRC}" O="${KERNEL_BUILD}" -j"$(nproc)" bzImage modules

kernel_release="$(make -s -C "${KERNEL_SRC}" O="${KERNEL_BUILD}" kernelrelease)"
make -C "${KERNEL_SRC}" O="${KERNEL_BUILD}" INSTALL_MOD_PATH="${INITRAMFS_ROOT}" modules_install
depmod -b "${INITRAMFS_ROOT}" "${kernel_release}"

install -d \
    "${INITRAMFS_ROOT}/bin" \
    "${INITRAMFS_ROOT}/dev" \
    "${INITRAMFS_ROOT}/etc" \
    "${INITRAMFS_ROOT}/lib/modules" \
    "${INITRAMFS_ROOT}/mnt" \
    "${INITRAMFS_ROOT}/persistent" \
    "${INITRAMFS_ROOT}/proc" \
    "${INITRAMFS_ROOT}/run" \
    "${INITRAMFS_ROOT}/sbin" \
    "${INITRAMFS_ROOT}/sys" \
    "${INITRAMFS_ROOT}/tmp" \
    "${INITRAMFS_ROOT}/usr/local/bin"

copy_binary_with_libs "$(command -v busybox)" "/bin/busybox"
for applet in cat chmod cp echo grep ln ls mkdir mount poweroff rm sh sleep sync test umount uname; do
    ln -sf /bin/busybox "${INITRAMFS_ROOT}/bin/${applet}"
done

copy_binary_with_libs "$(command -v mkfs.ext4)" "/sbin/mkfs.ext4"

install -Dm755 "${REPO_ROOT}/zig-out/bin/zram-config" "${INITRAMFS_ROOT}/usr/local/bin/zram-config"
install -Dm755 "${REPO_ROOT}/zig-out/bin/overlay" "${INITRAMFS_ROOT}/usr/local/bin/overlay"
install -Dm755 "${REPO_ROOT}/.github/vm/init" "${INITRAMFS_ROOT}/init"
install -Dm755 "${REPO_ROOT}/.github/vm/test-zram-config.bash" "${INITRAMFS_ROOT}/usr/local/bin/test-zram-config.bash"
install -Dm644 "${REPO_ROOT}/.github/vm/zram-config.json" "${INITRAMFS_ROOT}/etc/zram-config.json"

mknod -m 600 "${INITRAMFS_ROOT}/dev/console" c 5 1
mknod -m 666 "${INITRAMFS_ROOT}/dev/null" c 1 3

dd if=/dev/zero of="${PERSIST_IMG}" bs=1M count=256 status=none
mkfs.ext4 -F "${PERSIST_IMG}"
trap 'mountpoint -q "${PERSIST_MNT}" && umount "${PERSIST_MNT}"' EXIT
mount -o loop "${PERSIST_IMG}" "${PERSIST_MNT}"
mkdir -p "${PERSIST_MNT}/test-target"
printf 'lower-file\n' > "${PERSIST_MNT}/test-target/lower.txt"
umount "${PERSIST_MNT}"
trap - EXIT

(
    cd "${INITRAMFS_ROOT}"
    find . -print0 | cpio --null --create --format=newc --quiet | gzip -9 > "${OUT_DIR}/initramfs.cpio.gz"
)
