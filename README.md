# zram-config
Complete zram config utility for swap, directory &amp; log 
Usefull for IoT / maker projects for reducing SD, Nand and Emmc block wear via log operations.
Uses Zram to minimise precious memory footprint and extremely infrequent write outs.

Uses a ztab table in /etc/ztab where any combination and number of zram drives can be created.

_____
### Menu
1. [Install](#install)
2. [Config](#config)
3. [It is working ?](#it-is-working)
4. [Uninstall](#uninstall-)

### Install
    sudo apt-get install git
    git clone https://github.com/StuartIanNaylor/zram-config
    cd zram-config
    sudo sh install.sh
    

### Customize
In the file `/etc/ztab` `sudo nano /etc/ztab` to edit:
`#` To comment out any line
Add new drives with the first collumn providing the drive type and then drive details seperated by tab

All algorithm in /proc/crypto are supported but only lzo/lz4 have zramctl text strings.
lz4 is the fastest whilst deflate(zlib) has much better text compression.

mem_limit is compressed memory limit and will set a hard memory limit for sys admin.

disk_size is virtual uncompressed size approx 220-450% of mem allocated depending on algorithm and input file.
Much higher than the compression alg is capable will waste mem as there is an approx 0.1% mem overhead even when empty.

swap_priority set zram over alternative swap devices.

page-cluster 0 means tuning to singular pages rather than default 3 which caches 8 for HDD tuning.

swappiness 80 due to improved performance of zram allows more usage without effect of raising from default 60.

zram_dir is the directory you wish to hold in zram, the original is moved to a bind mount bind_dir and is synchronised on start/stop and write commands.

bind_dir is a directory where the original dir will be mounted for sync purposes. Usually in /opt or /var, name optional.

oldlog_dir will enable logrotation to an off device directory whilst retaining only live logs in zram.  Usually in /opt or /var, name optional.

If you need multiple zram swaps or zram dirs just create another entry in /ect/ztab.

Stop the service `sudo service zram-config stop` edit /etc/ztab `sudo nano /etc/ztab` start the service `sudo service zram-config start`
```
# swap	alg	mem_limit	disk_size	swap_priority	page-cluster	swappiness
swap	lz4	250M		750M		75		0		80

# dir	alg	mem_limit	disk_size	zram_dir	bind_dir
dir	lz4	20M		60M		/var/backups	/opt/backups.bind

# log	alg	mem_limit	disk_size	zram_dir	bind_dir	oldlog_dir
log	lz4	20M		60M		/var/log	/opt/log.bind	/opt/oldlog
```



### It is working?
```
pi@raspberrypi:~/zramdrive $ zramctl
NAME       ALGORITHM DISKSIZE  DATA  COMPR TOTAL STREAMS MOUNTPOINT
/dev/zram0 lz4            15M    5M 348.4K  772K       1 /var/log
/dev/zram1 lz4         650.2M    4K    64B    4K       1 [SWAP]
/dev/zram2 lz4            60M  4.7M 295.5K  568K       1 /var/backups
…
sudo zram-config write
…
This will write out any updated files to persistant storage, usefull for new app installs with new logs without need for start/stop or reboot
…
sudo logrotate -vf /etc/logrotate.conf
…
Force new logrotate truncate logs and move oldlogs to oldlog_dir
…
pi@raspberrypi:~ $ cat /proc/mounts
/dev/root / ext4 rw,noatime,data=ordered 0 0
devtmpfs /dev devtmpfs rw,relatime,size=217604k,nr_inodes=54401,mode=755 0 0
sysfs /sys sysfs rw,nosuid,nodev,noexec,relatime 0 0
proc /proc proc rw,relatime 0 0
tmpfs /dev/shm tmpfs rw,nosuid,nodev 0 0
devpts /dev/pts devpts rw,nosuid,noexec,relatime,gid=5,mode=620,ptmxmode=000 0 0
tmpfs /run tmpfs rw,nosuid,nodev,mode=755 0 0
tmpfs /run/lock tmpfs rw,nosuid,nodev,noexec,relatime,size=5120k 0 0
tmpfs /sys/fs/cgroup tmpfs ro,nosuid,nodev,noexec,mode=755 0 0
cgroup /sys/fs/cgroup/systemd cgroup rw,nosuid,nodev,noexec,relatime,xattr,relea                                       se_agent=/lib/systemd/systemd-cgroups-agent,name=systemd 0 0
cgroup /sys/fs/cgroup/freezer cgroup rw,nosuid,nodev,noexec,relatime,freezer 0 0
cgroup /sys/fs/cgroup/net_cls cgroup rw,nosuid,nodev,noexec,relatime,net_cls 0 0
cgroup /sys/fs/cgroup/devices cgroup rw,nosuid,nodev,noexec,relatime,devices 0 0
cgroup /sys/fs/cgroup/cpu,cpuacct cgroup rw,nosuid,nodev,noexec,relatime,cpu,cpu                                       acct 0 0
cgroup /sys/fs/cgroup/blkio cgroup rw,nosuid,nodev,noexec,relatime,blkio 0 0
debugfs /sys/kernel/debug debugfs rw,relatime 0 0
systemd-1 /proc/sys/fs/binfmt_misc autofs rw,relatime,fd=30,pgrp=1,timeout=0,min                                       proto=5,maxproto=5,direct 0 0
sunrpc /run/rpc_pipefs rpc_pipefs rw,relatime 0 0
mqueue /dev/mqueue mqueue rw,relatime 0 0
configfs /sys/kernel/config configfs rw,relatime 0 0
/dev/mmcblk0p1 /boot vfat rw,relatime,fmask=0022,dmask=0022,codepage=437,iochars                                       et=ascii,shortname=mixed,errors=remount-ro 0 0
/dev/root /opt/backups.bind ext4 rw,noatime,data=ordered 0 0
/dev/zram1 /var/backups ext4 rw,nosuid,nodev,noexec,relatime,data=ordered 0 0
/dev/root /opt/log.bind ext4 rw,noatime,data=ordered 0 0
/dev/zram2 /var/log ext4 rw,nosuid,nodev,noexec,relatime,data=ordered 0 0
tmpfs /run/user/1000 tmpfs rw,nosuid,nodev,relatime,size=44384k,mode=700,uid=100                                       0,gid=1000 0 0
…
pi@raspberrypi:~ $ cat /proc/swaps
Filename                                Type            Size    Used    Priority
/dev/zram0                              partition       767996  0       75
/var/swap                               file            102396  0       -2

```



| Compressor name	     | Ratio	| Compression | Decompress. |
|------------------------|----------|-------------|-------------|
|zstd 1.3.4 -1	         | 2.877	| 470 MB/s	  | 1380 MB/s   |
|zlib 1.2.11 -1	         | 2.743    | 110 MB/s    | 400 MB/s    |
|brotli 1.0.2 -0	     | 2.701	| 410 MB/s	  | 430 MB/s    |
|quicklz 1.5.0 -1	     | 2.238	| 550 MB/s	  | 710 MB/s    |
|lzo1x 2.09 -1	         | 2.108	| 650 MB/s	  | 830 MB/s    |
|lz4 1.8.1	             | 2.101    | 750 MB/s    | 3700 MB/s   |
|snappy 1.1.4	         | 2.091	| 530 MB/s	  | 1800 MB/s   |
|lzf 3.6 -1	             | 2.077	| 400 MB/s	  | 860 MB/s    |


### Uninstall
```
sudo sh /usr/local/share/zram-config/uninstall.sh
```


### Git Branches & Update
From the command line, enter `cd <path_to_local_repo>` so that you can enter commands for your repository.
Enter `git add --all` at the command line to add the files or changes to the repository
Enter `git commit -m '<commit_message>'` at the command line to commit new files/changes to the local repository. For the <commit_message> , you can enter anything that describes the changes you are committing.
Enter `git push`  at the command line to copy your files from your local repository to remote.

### Reference
https://www.kernel.org/doc/Documentation/blockdev/zram.txt
