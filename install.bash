#!/usr/bin/env bash

BASEDIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: You need to be ROOT (sudo can be used)."
  exit 1
fi
if [[ $(systemctl is-active zram-config.service) == "active" ]]; then
  echo -e "ERROR: zram-config service is still running.\\nPlease run \"sudo ${BASEDIR}/update.bash\" to update zram-config instead."
  exit 1
fi
if [[ -f /usr/local/sbin/zram-config ]]; then
  echo -e "ERROR: zram-config is already installed.\\nPlease run \"sudo ${BASEDIR}/update.bash\" to update zram-config instead."
  exit 1
fi

if ! dpkg -s 'gcc' 'make' 'libc6-dev' &> /dev/null; then
  echo "Installing needed packages (gcc, make, libc6-dev)"
  apt-get install --yes gcc make libc6-dev || exit 1
fi
if [[ "$(grep -o '^ID=.*$' /etc/os-release | cut -d'=' -f2)" == "ubuntu" ]] && [[ $(bc -l <<< "$(grep -o '^VERSION_ID=.*$' /etc/os-release | cut -d'=' -f2 | tr -d '"') >= 21.10") -eq 1 ]]; then
  echo "Install zram module package for Ubuntu (linux-modules-extra-raspi)"
  if ! dpkg -s 'linux-modules-extra-raspi' &> /dev/null; then
    apt-get install --yes linux-modules-extra-raspi || exit 1
  fi
fi

make --always-make --directory="${BASEDIR}/overlayfs-tools"

echo "Installing zram-config files"
install -m 755 "${BASEDIR}/zram-config" /usr/local/sbin/
install -m 644 "${BASEDIR}/zram-config.service" /etc/systemd/system/zram-config.service
install -m 644 "${BASEDIR}/zram-config-shutdown.service" /etc/systemd/system/zram-config-shutdown.service
install -m 644 "${BASEDIR}/ztab" /etc/ztab
mkdir -p /usr/local/share/zram-config/log
ln -s /usr/local/share/zram-config/log /var/log/zram-config
install -m 755 "${BASEDIR}/uninstall.bash" /usr/local/share/zram-config/uninstall.bash
install -m 644 "${BASEDIR}/zram-config.logrotate" /etc/logrotate.d/zram-config
mkdir -p /usr/local/lib/zram-config/
install -m 755 "${BASEDIR}/overlayfs-tools/overlay" /usr/local/lib/zram-config/overlay
echo "ReadWritePaths=/usr/local/share/zram-config/log" >> /lib/systemd/system/logrotate.service

echo "Starting zram-config.service"
systemctl daemon-reload
systemctl enable --now zram-config.service zram-config-shutdown.service
until [[ $(systemctl show -p SubState --value zram-config) == "dead" ]]; do
  sleep 5
done

echo "#####     zram-config is now installed and running     #####"
echo "#####       edit /etc/ztab to configure options        #####"
