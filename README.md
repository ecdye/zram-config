# zram-config
Complete zram config utility for swap, directory &amp; log 
Usefull for IoT / maker projects for reducing SD, Nand and Emmc block wear via log operations.
Uses Zram to minimise precious memory footprint and extremely infrequent write outs and near ram speed working dirs.

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

page-cluster 0 means tuning to singular pages rather than default 3 which caches 8 for HDD tuning, which can lower latency.

swappiness 80 due to improved performance of zram allows more usage without effect of raising from default 60. Can be up to 100 but will increase process queue on intense load such as boot.

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
This will write out any updated files to persistant storage.
Usefull for new app installs with new logs without need for start/stop or reboot.
Can be used with a cron job for periodic backup of live logs.
…
sudo logrotate -vf /etc/logrotate.conf
…
Force new logrotate truncate logs and move oldlogs to oldlog_dir
…
pi@raspberrypi:~ $ cat /proc/mounts
/dev/root / ext4 rw,noatime,data=ordered 0 0
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
…
pi@raspberrypi:~/zram-config $ cat /usr/local/share/zram-config/log/zram-config.log
zram-config start 20190330_062747Z
ztab create log lz4 20M 60M /var/log /opt/log.bind /opt/oldlog
Warning: Stopping rsyslog.service, but it can still be activated by:
  syslog.socket
mount: /var/log bound on /opt/log.bind.
mount: /opt/log.bind propagation flags changed.
insmod /lib/modules/4.14.98+/kernel/mm/zsmalloc.ko
insmod /lib/modules/4.14.98+/kernel/drivers/block/zram/zram.ko
zram0 created comp_algorithm=lz4 mem_limit=20M disksize=60M
mke2fs 1.43.4 (31-Jan-2017)
fs_types for mke2fs.conf resolution: 'ext4', 'small'
Discarding device blocks: done
Filesystem label=
…
pi@raspberrypi:~/zram-config $ ls /opt/oldlog
auth.log.1       debug.1           kern.log.1     term.log.1.gz
auth.log.2.gz    dpkg.log.1        messages.1     user.log.1
btmp.1           error.log.1       messages.2.gz  wtmp.1
daemon.log.1     error.log.2.gz    syslog.1       zram-config.log.1
daemon.log.2.gz  history.log.1.gz  syslog.2.gz
…
```

### Performance
LZO/4 offer the best performance and for swaps they are probably the defacto choice.
You maybe have text based low impact directories such a /var/log /var/cache where highly
effective text compressors, such as deflate(zlib) & zstd are used in preference of disk size
and effective compression that can be up to 200% of what a LZ may achieve.
/tmp /run I am not so sure about incur any further load on what can be small blistering fast
ram mounted tmpfs as if memory gets short then zram swaps will provide.
That way your system is performance optimised and also memory optimised via zram swap,
with compression overhead of some common working directories.
The choice is yours though and its very dependent on the loading you commonly run with.
Its only at intense load the slight overhead of zram compression becomes noticeable.
A Pi-Zero obviously shows far more effect than a Pi-3B+
LZO-RLE has roled out in the latest kernels and is the new default for zram and still don't
know if that will change my own personal pick of LZ4.
Until I can find another comparative benchmark that includes all this list is a good yardstick.

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

With Swaps Zram changes what are static assumptions of HHD providing swaps in terms of swapiness
and page-cache where default swapiness is 60 and page-cache is 3 to buffer page-writes of 8.
Employing near memory based swaps needs tuning for near memory based swaps and the current defaults
are far from optimised.
Depending on avg load Zram will benefit from a setting of 80 -100 and changing page-cache to 0 so that
singular pages are written will greatly reduce latency.
Its a shame swapiness is not dynamically based on load as for many systems there is often a huge difference
in boot startup to settled load.
In some cases you may find you are reducing swapiness purely because of boot load.
### Uninstall
```
sudo sh /usr/local/share/zram-config/uninstall.sh
```


### Git Branches & Update
From the command line, enter `cd <path_to_local_repo>` so that you can enter commands for your repository.

Enter `git add --all` at the command line to add the files or changes to the repository.

Enter `git commit -m '<commit_message>'` at the command line to commit new files/changes to the local repository. For the <commit_message> , you can enter anything that describes the changes you are committing.

Enter `git push`  at the command line to copy your files from your local repository to remote.

### Reference
https://www.kernel.org/doc/Documentation/blockdev/zram.txt
