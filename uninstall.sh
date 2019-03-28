#!/bin/bash

if [ "$(id -u)" -eq 0 ]
then
	service zram-config stop
	systemctl disable zram-config
	rm /etc/systemd/system/zram-config.service
	rm /usr/local/bin/zram-config
	rm /etc/ztab


	echo "zram-config is uninstalled, removing the uninstaller in progress"
	rm -rf /usr/local/share/zram-config
	echo "##### Reboot isn't needed #####"
else
	echo "You need to be ROOT (sudo can be used)"
fi
