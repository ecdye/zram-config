#!/usr/bin/env bash

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: You need to be ROOT (sudo can be used)."
  exit 1
fi
if ! [[ -f /usr/local/sbin/zram-config ]]; then
  echo "ERROR: zram-config is not installed."
  exit 1
fi

zram-config "stop"
systemctl disable zram-config.service
rm -f /etc/systemd/system/zram-config.service
sed -i '\|^ReadWritePaths=/usr/local/share/zram-config/log$|d' /lib/systemd/system/logrotate.service
systemctl daemon-reload
rm -f /usr/local/sbin/zram-config
rm -f /etc/logrotate.d/zram-config
rm -f /etc/ztab
rm -rf /usr/local/lib/zram-config
rm -rf /usr/local/share/zram-config

echo "#####     zram-config has been uninstalled     #####"
echo "#####           Reboot is not needed           #####"
