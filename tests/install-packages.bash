#!/usr/bin/env bash

export DEBIAN_FRONTEND="noninteractive"

apt-get --quiet update
apt-get --quiet install --yes gcc meson libc6-dev
apt-get --quiet autoremove --yes
systemctl mask rpi-eeprom-update.service hciuart.service systemd-logind.service
rm -f /var/lib/apt/lists/lock
rm -f /var/cache/apt/archives/lock
rm -f /var/lib/dpkg/lock*

# vim: ts=4 sts=4 sw=4 et
