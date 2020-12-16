#!/usr/bin/env bash

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: You need to be ROOT (sudo can be used)."
  exit 1
fi
if [[ $(systemctl is-active zram-config.service) == "active" ]]; then
  echo "ERROR: zram-config service is still running. Please run \"sudo /usr/local/share/zram-config/uninstall.bash\" to uninstall zram-config before running this."
  exit 1
fi
if [[ -f /usr/local/sbin/zram-config ]]; then
  echo "ERROR: zram-config is already installed. Please run \"sudo /usr/local/share/zram-config/uninstall.bash\" to uninstall zram-config before running this."
  exit 1
fi

echo "Installing needed packages (make, libattr1-dev)"
if ! dpkg -s 'make' 'libattr1-dev' &> /dev/null; then
  apt-get install --yes make libattr1-dev || exit 1
fi

cd overlayfs-tools || exit 1
make
cd ..

echo "Installing zram-config files"
install -m 755 zram-config /usr/local/sbin/
install -m 644 zram-config.service /etc/systemd/system/zram-config.service
install -m 644 ztab /etc/ztab
mkdir -p /usr/local/share/zram-config/log
install -m 644 uninstall.bash /usr/local/share/zram-config/uninstall.bash
install -m 644 ro-root.sh /usr/local/share/zram-config/ro-root.sh
install -m 644 zram-config.logrotate /etc/logrotate.d/zram-config
mkdir -p /usr/local/lib/zram-config/
install -m 755 overlayfs-tools/overlay /usr/local/lib/zram-config/overlay

echo "Starting zram-config.service"
systemctl daemon-reload
systemctl enable --now zram-config.service

echo "#####   zram-config is now installed and running   #####"
echo "#####     edit /etc/ztab to configure options      #####"
