#!/usr/bin/env bash

apt-get --quiet update
apt-get --quiet upgrade --yes
apt-get --quiet install --yes gcc make libc6-dev
apt-get --quiet autoremove --yes
rm -f /var/lib/apt/lists/lock
rm -f /var/cache/apt/archives/lock
rm -f /var/lib/dpkg/lock*
