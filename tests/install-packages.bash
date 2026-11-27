#!/usr/bin/env bash

export DEBIAN_FRONTEND="noninteractive"

apt-get --quiet update
apt-get --quiet install --yes gcc meson libc6-dev
apt-get --quiet autoremove --yes
systemctl mask rpi-eeprom-update.service hciuart.service systemd-logind.service

# Raspberry Pi OS arms the hardware watchdog from systemd, which resets the
# emulated board as soon as systemd starts under QEMU.
mkdir -p /etc/systemd/system.conf.d
printf '[Manager]\nRuntimeWatchdogSec=off\nRebootWatchdogSec=off\n' > /etc/systemd/system.conf.d/99-qemu-no-watchdog.conf

# The image ships a locked pi user with a nologin shell; make it usable for the
# test login and allow non-interactive sudo.
usermod --shell /bin/bash pi
echo "pi:raspberry" | chpasswd
echo "pi ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/010_pi-nopasswd
chmod 440 /etc/sudoers.d/010_pi-nopasswd
systemctl disable userconfig.service
rm -f /var/lib/apt/lists/lock
rm -f /var/cache/apt/archives/lock
rm -f /var/lib/dpkg/lock*

# vim: ts=4 sts=4 sw=4 et
