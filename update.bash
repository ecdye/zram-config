#!/usr/bin/env bash

BASEDIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS="$(grep -o '^ID=.*$' /etc/os-release | cut -d'=' -f2)"

if [[ "$(id -u)" -ne 0 ]]; then
    echo "ERROR: You need to be ROOT (sudo can be used)."
    exit 1
fi
if ! [[ -s /usr/local/sbin/zram-config || -s /usr/sbin/zram-config ]]; then
    echo -e "ERROR: zram-config is not installed.\\nPlease run \"sudo ${BASEDIR}/install.bash\" to install zram-config instead."
    exit 1
fi

if [[ $OS == "alpine" ]] && ! [[ "$(apk info 2> /dev/null | grep -E '^(gcc|meson|fts-dev|linux-headers|util-linux-misc|musl-dev)' | tr '\n' ' ')" == "fts-dev gcc meson util-linux-misc musl-dev linux-headers " ]]; then
    echo "Installing needed packages (gcc, meson, fts-dev, linux-headers, util-linux-misc, musl-dev)"
    apk add gcc meson fts-dev linux-headers util-linux-misc musl-dev || exit 1
elif ! dpkg -s 'gcc' 'meson' 'libc6-dev' &> /dev/null; then
    echo "Installing needed packages (gcc, meson, libc6-dev)"
    apt-get install --yes gcc meson libc6-dev || exit 1
fi

if [[ $OS == "ubuntu" ]] && [[ $(bc -l <<< "$(grep -o '^VERSION_ID=.*$' /etc/os-release | cut -d'=' -f2 | tr -d '"') >= 21.10") -eq 1 ]]; then
    echo "Install zram module package for Ubuntu (linux-modules-extra-raspi)"
    if ! dpkg -s 'linux-modules-extra-raspi' &> /dev/null; then
        apt-get install --yes linux-modules-extra-raspi || exit 1
    fi
fi

if [[ $1 != "custom" ]]; then
    git -C "$BASEDIR" fetch origin
    git -C "$BASEDIR" clean --force -x -d
    git -C "$BASEDIR" reset --hard --recurse-submodules origin main
    git -C "$BASEDIR" submodule update --init --recursive
fi

rm -rf "$BASEDIR"/overlayfs-tools/builddir
meson setup "$BASEDIR"/overlayfs-tools/builddir "$BASEDIR"/overlayfs-tools || exit 1
meson compile -C "$BASEDIR"/overlayfs-tools/builddir || exit 1
meson install -C "$BASEDIR"/overlayfs-tools/builddir || exit 1

echo "Stopping zram-config service"
if [[ $OS == "alpine" ]]; then
    rc-service zram-config stop
else
    systemctl stop zram-config.service
fi

echo "Updating zram-config files"
if [[ "$OS" == "alpine" ]]; then
    install -m 755 "$BASEDIR"/zram-config /usr/sbin/
    install -m 755 "$BASEDIR"/service/OpenRC/zram-config.openrc /etc/init.d/zram-config
else
    install -m 755 "$BASEDIR"/zram-config /usr/local/sbin/
    install -m 644 "$BASEDIR"/service/SystemD/zram-config.service /etc/systemd/system/zram-config.service
    if ! grep -qs "ReadWritePaths=/usr/local/share/zram-config/log" /lib/systemd/system/logrotate.service; then
        echo "ReadWritePaths=/usr/local/share/zram-config/log" >> /lib/systemd/system/logrotate.service
    fi
fi
install -m 755 "$BASEDIR"/uninstall.bash /usr/local/share/zram-config/uninstall.bash
if ! [[ -f /etc/ztab ]]; then
    install -m 644 "$BASEDIR"/ztab /etc/ztab
fi
sed -i -E 's/(\tbind_dir|\t\/\w*\.bind)//g' /etc/ztab # Remove bind_dir and /path.bind from ztab
if ! [[ -d /usr/local/share/zram-config/log ]]; then
    mkdir -p /usr/local/share/zram-config/log
fi
if ! [[ -h /var/log/zram-config ]]; then
    ln -s /usr/local/share/zram-config/log /var/log/zram-config
fi
if ! [[ -f /etc/logrotate.d/zram-config ]]; then
    install -m 644 "$BASEDIR"/service/zram-config.logrotate /etc/logrotate.d/zram-config
fi
if ! [[ -d /usr/local/lib/zram-config ]]; then
    mkdir -p /usr/local/lib/zram-config
fi

if ! [[ -d /usr/local/share/man/man1 ]]; then
    mkdir -p /usr/local/share/man/man1/
fi
install -m 644 "$BASEDIR"/doc/man/zram-config.1 /usr/local/share/man/man1/zram-config.1
mandb --quiet

echo "Starting zram-config service"
if [[ $OS == "alpine" ]]; then
    rc-update add zram-config boot
    rc-service zram-config start
else
    systemctl daemon-reload
    systemctl enable --now zram-config.service
fi

echo "#####        zram-config has been updated         #####"
echo "#####     edit /etc/ztab to configure options     #####"

# vim: ts=4 sts=4 sw=4 et
