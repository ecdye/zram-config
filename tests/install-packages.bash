#!/usr/bin/env bash

export DEBIAN_FRONTEND="noninteractive"
export NONINTERACTIVE=1

apt-get --quiet update
apt-get --quiet install --yes build-essential procps curl file git
apt-get --quiet autoremove --yes
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
/home/linuxbrew/.linuxbrew/bin/brew install zig
systemctl mask rpi-eeprom-update.service hciuart.service systemd-logind.service
rm -f /var/lib/apt/lists/lock
rm -f /var/cache/apt/archives/lock
rm -f /var/lib/dpkg/lock*

# vim: ts=4 sts=4 sw=4 et
