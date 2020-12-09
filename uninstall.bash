#!/usr/bin/env bash

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: You need to be ROOT (sudo can be used)."
  exit 1
fi

systemctl disable --now zram-config.service
rm -f /etc/systemd/system/zram-config.service
rm -f /usr/local/bin/zram-config
rm -f /etc/logrotate.d/zram-config
rm -f /etc/ztab
rm -rf /usr/local/lib/zram-config
rm -rf /usr/local/share/zram-config

echo "##### Reboot isn't needed #####"
