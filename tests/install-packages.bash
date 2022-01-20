#!/usr/bin/env bash

export DEBIAN_FRONTEND="noninteractive"

apt-get --quiet update
# apt-get --quiet upgrade --yes
apt-get --quiet install --yes gcc make libc6-dev
apt-get --quiet autoremove --yes
systemctl mask systemd-logind.service
rm -f /var/lib/apt/lists/lock
rm -f /var/cache/apt/archives/lock
rm -f /var/lib/dpkg/lock*
