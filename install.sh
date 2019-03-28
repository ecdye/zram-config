#!/bin/bash

systemctl -q is-active zram-config  && { echo "ERROR: zram-config service is still running. Please run \"sudo service zram-config stop\" to stop it and uninstall"; exit 1; }
[ "$(id -u)" -eq 0 ] || { echo "You need to be ROOT (sudo can be used)"; exit 1; }
[ -d /usr/local/bin/zram-config ] && { echo "zram-config is already installed, uninstall first"; exit 1; }


# zram-config install 
install -m 755 zram-config /usr/local/bin/
install -m 644 zram-config.service /etc/systemd/system/zram-config.service
install -m 644 ztab /etc/ztab
mkdir -p /usr/local/share/zram-config
install -m 644 uninstall.sh /usr/local/share/zram-config/uninstall.sh
systemctl enable zram-config

echo "#####          Reboot to activate zram-config         #####"
echo "#####       edit /etc/ztab to configure options       #####"


