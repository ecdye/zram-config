#!/usr/bin/env bash

BASEDIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: You need to be ROOT (sudo can be used)."
  exit 1
fi
if ! [[ -f /usr/local/sbin/zram-config ]]; then
  echo "ERROR: zram-config is not installed."
  exit 1
fi

zram-config "stop"
tar -cf "${BASEDIR}/logs.tar" --directory=/usr/local/share/zram-config log
systemctl disable zram-config.service zram-config-shutdown.service
rm -f /etc/systemd/system/zram-config.service /etc/systemd/system/zram-config-shutdown.service
sed -i '\|^ReadWritePaths=/usr/local/share/zram-config/log$|d' /lib/systemd/system/logrotate.service
systemctl daemon-reload
rm -f /usr/local/sbin/zram-config
rm -f /etc/logrotate.d/zram-config
rm -f /etc/ztab
rm -rf /usr/local/lib/zram-config
rm -rf /usr/local/share/zram-config
rm -f /var/log/zram-config

echo "#####     zram-config has been uninstalled     #####"
echo "#####           Reboot is not needed           #####"
