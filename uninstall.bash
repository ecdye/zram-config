#!/usr/bin/env bash

BASEDIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS="$(grep -o '^ID=.*$' /etc/os-release | cut -d'=' -f2)"

if [[ "$(id -u)" -ne 0 ]]; then
    echo "ERROR: You need to be ROOT (sudo can be used)."
    exit 1
fi
if ! [[ -f /usr/local/sbin/zram-config || -f /usr/sbin/zram-config ]]; then
    echo "ERROR: zram-config is not installed."
    exit 1
fi

zram-config "stop"
tar -czf "${BASEDIR}/logs.tar.gz" -C /usr/local/share/zram-config/log .
if [[ $OS == "alpine" ]]; then
    rc-service zram-config stop
    rc-update del zram-config boot
    if [[ -f /etc/periodic/daily/zsync ]]; then
        rm -f /etc/periodic/daily/zsync
    fi
    rm -f /etc/init.d/zram-config
    rm -f /usr/sbin/zram-config
else
    systemctl disable zram-config.service
    rm -f /etc/systemd/system/zram-config.service
    if [[ -f /etc/systemd/system/zsync.timer ]]; then
        systemctl disable zsync.timer
        rm -f /etc/systemd/system/zsync.*
    fi
    sed -i '\|^ReadWritePaths=/usr/local/share/zram-config/log$|d' /lib/systemd/system/logrotate.service
    systemctl daemon-reload
    rm -f /usr/local/sbin/zram-config
fi
rm -f /etc/logrotate.d/zram-config
rm -f /etc/ztab
rm -rf /usr/local/lib/zram-config
rm -rf /usr/local/share/zram-config
rm -f /var/log/zram-config
rm -f /usr/local/share/man/man1/zram-config.1
mandb --quiet

echo "#####     zram-config has been uninstalled     #####"
echo "#####           Reboot is not needed           #####"

# vim: ts=4 sts=4 sw=4 et
