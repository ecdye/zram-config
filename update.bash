#!/usr/bin/env bash

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: You need to be ROOT (sudo can be used)."
  exit 1
fi
if ! [[ -f /usr/local/sbin/zram-config ]]; then
  echo "ERROR: zram-config is not installed.\\nPlease run \"sudo ./install.bash\" to install zram-config instead."
  exit 1
fi

if ! dpkg -s 'gcc' 'make' 'libattr1-dev' &> /dev/null; then
  apt-get install --yes gcc make libattr1-dev || exit 1
fi

git fetch origin
git fetch --tags --force --prune
git clean --force -x -d
git checkout main
git reset --hard origin/main
git submodule update --remote

cd overlayfs-tools || exit 1
rm -f overlay
make
cd ..

echo "Stopping zram-config.service"
zram-config "stop"

echo "Updating zram-config files"
install -m 755 zram-config /usr/local/sbin/
install -m 644 zram-config.service /etc/systemd/system/zram-config.service
install -m 755 uninstall.bash /usr/local/share/zram-config/uninstall.bash
if ! [[ -f /etc/ztab ]]; then
  install -m 644 ztab /etc/ztab
fi
if ! [[ -d /usr/local/share/zram-config/log ]]; then
  mkdir -p /usr/local/share/zram-config/log
fi
if ! [[ -f /etc/logrotate.d/zram-config ]]; then
  install -m 644 zram-config.logrotate /etc/logrotate.d/zram-config
fi
if ! [[ -d /usr/local/lib/zram-config ]]; then
  mkdir -p /usr/local/lib/zram-config
fi
install -m 755 overlayfs-tools/overlay /usr/local/lib/zram-config/overlay
if ! grep -qs "ReadWritePaths=/usr/local/share/zram-config/log" /lib/systemd/system/logrotate.service; then
  echo "ReadWritePaths=/usr/local/share/zram-config/log" >> /lib/systemd/system/logrotate.service
fi

echo "Starting zram-config.service"
systemctl daemon-reload
systemctl start zram-config.service

echo "#####          zram-config has been updated           #####"
echo "#####       edit /etc/ztab to configure options       #####"
