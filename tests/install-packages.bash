#!/usr/bin/env bash

export DEBIAN_FRONTEND="noninteractive"

apt-get --quiet update
apt-get --quiet install --yes gcc meson libc6-dev minisign
apt-get --quiet autoremove --yes

PUBKEY="RWSGOq2NVecA2UPNdBUZykf1CCb147pkmdtYxgb3Ti+JO/wCYvhbAb/U"

TARBALL_NAME="zig-arm-linux-0.15.1.tar.xz"
MIRRORS_URL="https://ziglang.org/download/community-mirrors.txt"

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
                tar -xf "$TARBALL_NAME"
                mv "${TARBALL_NAME%.tar.xz}" "/opt/zig"
                /opt/zig/bin/zig version
                break
            else
                echo "❌ Verification failed for $MIRROR"
            fi
        fi
    fi
done

systemctl mask rpi-eeprom-update.service hciuart.service systemd-logind.service
rm -f /var/lib/apt/lists/lock
rm -f /var/cache/apt/archives/lock
rm -f /var/lib/dpkg/lock*

# vim: ts=4 sts=4 sw=4 et
