#!/bin/bash


git clone https://github.com/StuartIanNaylor/overlayfs-tools -b Arch
cd overlayfs-tools
make
cd ..


# zram-config install
install -m 755 zram-config /usr/local/bin/
install -m 644 zram-config.service /etc/systemd/system/zram-config.service
install -m 644 ztab /etc/ztab
mkdir -p /usr/local/share/zram-config
mkdir -p /usr/local/share/zram-config/log
install -m 644 uninstall.sh /usr/local/share/zram-config/uninstall.sh
install -m 644 ro-root.sh /usr/local/share/zram-config/ro-root.sh
install -m 644 zram-config.logrotate /etc/logrotate.d/zram-config
mkdir -p /usr/local/lib/zram-config/

install -m 755 overlayfs-tools/overlay /usr/local/lib/zram-config/overlay
systemctl enable zram-config

echo "#####          Reboot to activate zram-config         #####"
echo "#####       edit /etc/ztab to configure options       #####"
