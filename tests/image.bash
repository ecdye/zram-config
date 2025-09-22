#!/usr/bin/env bash

imageFile() {
    local loopPrefix

    if [[ $1 == "mount" ]]; then
        loopPrefix="$(kpartx -asv "$2" | grep -oE "loop([0-9]+)" | head -n 1)"

        mkdir -p tests/{fs,kernel,dtb}
        mount -o rw -t ext4 "/dev/mapper/${loopPrefix}p2" "tests/fs"
        mount -o rw -t vfat "/dev/mapper/${loopPrefix}p1" "tests/fs/boot"
        sync
    elif [[ $1 == "umount" ]]; then
        sync
        umount tests/fs/boot
        umount tests/fs
        kpartx -d "$2"
    fi
}

downloadZig() {
    local PUBKEY="RWSGOq2NVecA2UPNdBUZykf1CCb147pkmdtYxgb3Ti+JO/wCYvhbAb/U"

    local TARBALL_NAME="zig-arm-linux-0.15.1.tar.xz"
    local MIRRORS_URL="https://ziglang.org/download/community-mirrors.txt"

    # Fetch mirrors list and shuffle
    mapfile -t SHUFFLED < <(curl -fsSL "$MIRRORS_URL" | shuf)

    for MIRROR in "${SHUFFLED[@]}"; do
        echo "Trying mirror: $MIRROR"
        TAR_URL="${MIRROR%/}/${TARBALL_NAME}?source=zram-config"
        SIG_URL="${MIRROR%/}/${TARBALL_NAME}.minisig?source=zram-config"

        if curl -fLo "$TARBALL_NAME" "$TAR_URL"; then
            if curl -fLo "$TARBALL_NAME.minisig" "$SIG_URL"; then
                if minisign -Vm "$TARBALL_NAME" -P "$PUBKEY"; then
                    echo "✅ Successfully fetched and verified Zig!"
                    tar -xf "$TARBALL_NAME" && rm $TARBALL_NAME
                    mkdir -p tests/fs/opt
                    mv "${TARBALL_NAME%.tar.xz}" "tests/fs/opt/zig"
                    break
                else
                    echo "❌ Verification failed for $MIRROR"
                fi
            fi
        fi
    done
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
    sed -i -e "s|DATESED|$(date)|" tests/run.exp
    rsync -avr --exclude="*.img" --exclude="*.sig" --exclude="tests/fs" --exclude="tests/dtb" --exclude="tests/kernel" ./ tests/fs/opt/zram-config
    downloadZig
    systemd-nspawn --directory="tests/fs" /opt/zram-config/tests/install-packages.bash
    echo "set enable-bracketed-paste off" >> tests/fs/etc/inputrc  # Prevents weird character output
    cp tests/fs/boot/kernel* tests/kernel
    # Compile a customized DTB
    git clone https://github.com/raspberrypi/utils.git
    cmake utils/dtmerge
    make
    sudo make install
    dtmerge tests/fs/boot/bcm2710-rpi-3-b-plus.dtb custom.dtb tests/fs/boot/overlays/disable-bt.dtbo uart0=on
    imageFile "umount" "$3"
elif [[ $1 == "copy-logs" ]]; then
    imageFile "mount" "$2"
    cp tests/fs/opt/zram-config/logs.tar.gz logs.tar.gz
    imageFile "umount" "$2"
fi

# vim: ts=4 sts=4 sw=4 et
