#!/usr/bin/env bash

export DEBIAN_FRONTEND="noninteractive"

apt-get --quiet update
# apt-get --quiet upgrade --yes
apt-get --quiet install --yes gcc make libc6-dev
apt-get --quiet autoremove --yes
systemctl set-default multi-user.target
ln -fs /lib/systemd/system/getty@.service /etc/systemd/system/getty.target.wants/getty@tty1.service
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin pi --noclear %I \$TERM
EOF
rm -f /var/lib/apt/lists/lock
rm -f /var/cache/apt/archives/lock
rm -f /var/lib/dpkg/lock*
