# zram-config
Complete zram config utility for swap, directory &amp; log 
Usefull for IoT / maker projects for reducing SD, Nand and Emmc block wear via log operations.
Uses Zram to minimise precious memory footprint and extremely infrequent write outs and near ram speed working dirs with memory compression ratios depending on compression alg chosen.

Uses a ztab table in /etc/ztab where any combination and number of zram drives can be created.
This branch uses a OverlayFS mount with zram so that syncFromDisk on start is not needed.
This should allow quicker boots and larger directories as no complete directory copy needed as its the
lower mount in the OverlayFS.
https://github.com/kmxz/overlayfs-tools many thanks to kmxz for the overlay merge tool.

Zram-config also allows a 'kiosk mode' where `sudo zram-config enable-ephemeral` on reboot will load the whole root into zram. There is no sync and zdir/zlog entries will be ignored as already included via the whole ro-root and zram upper. `sudo zram-config disable-ephemeral` and reboot to return to a normal system. https://blockdev.io/read-only-rpi/ and thanks to the original sources for another great script.


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
# swap  alg     mem_limit       disk_size       swap_priority   page-cluster    swappiness
swap    lz4     400M            1200M           75              0               90

# dir   alg     mem_limit       disk_size       target_dir              bind_dir
dir     lz4     50M             150M            /home/pi/MagicMirror    /magicmirror.bind

# log   alg     mem_limit       disk_size       target_dir              bind_dir                oldlog_dir
log     lz4     20M             60M             /var/log                /log.bind               /oldlog
```
Zram-config also allows a 'kiosk mode' where `sudo zram-config enable-ephemeral` on reboot will load the whole root into a ro OverlayFS with zram writeable upper. 
`sudo zram-config disable-ephemeral` and reboot to return to a normal system.
You may need to reboot after the rpi-update and then mkinitramfs -o /boot/initrd as a newer kernel maybe updated.
Check the 'Without NFS' section of https://blockdev.io/read-only-rpi/ as any problems you may have to remove the SD card and edit /boot/cmdline.txt removing the `init=/bin/ro-root.sh` entry.


### It is working?
```
pi@raspberrypi:~ $ zramctl
NAME       ALGORITHM DISKSIZE  DATA COMPR TOTAL STREAMS MOUNTPOINT
/dev/zram0 lz4           1.2G    4K   76B    4K       4 [SWAP]
/dev/zram1 lz4           150M 16.3M 25.1K  208K       4 /opt/zram/zram1
/dev/zram2 lz4            60M  7.5M  1.2M  1.7M       4 /opt/zram/zram2
```
```
pi@raspberrypi:~ $ df
Filesystem     1K-blocks    Used Available Use% Mounted on
/dev/root       14803620 2558152  11611220  19% /
devtmpfs          470116       0    470116   0% /dev
tmpfs             474724  223868    250856  48% /dev/shm
tmpfs             474724   12284    462440   3% /run
tmpfs               5120       4      5116   1% /run/lock
tmpfs             474724       0    474724   0% /sys/fs/cgroup
/dev/mmcblk0p1     44220   22390     21831  51% /boot
/dev/zram1        132384     280    121352   1% /opt/zram/zram1
overlay1          132384     280    121352   1% /home/pi/MagicMirror
/dev/zram2         55408    3460     47648   7% /opt/zram/zram2
overlay2           55408    3460     47648   7% /var/log
tmpfs              94944       0     94944   0% /run/user/1000
```
```
cat /etc/ztab
# swap  alg     mem_limit       disk_size       swap_priority   page-cluster    swappiness
swap    lz4     400M            1200M           75              0               90

# dir   alg     mem_limit       disk_size       target_dir              bind_dir
dir     lz4     50M             150M            /home/pi/MagicMirror    /magicmirror.bind

# log   alg     mem_limit       disk_size       target_dir              bind_dir                oldlog_dir
log     lz4     20M             60M             /var/log                /log.bind               /oldlog
```
```
pi@raspberrypi:~ $ free -h
              total        used        free      shared  buff/cache   available
Mem:           927M        206M        184M        233M        535M        434M
Swap:          1.3G          0B        1.3G
```
```
pi@raspberrypi:~ $ swapon
NAME       TYPE      SIZE USED PRIO
/dev/zram0 partition 1.2G   0B   75
/var/swap  file      100M   0B   -2
```
```
pi@raspberrypi:/opt/zram $ ls
log.bind  magicmirror.bind  oldlog  zram1  zram2
```
```
pi@raspberrypi:/opt/zram $ top
top - 23:18:21 up  1:28,  2 users,  load average: 0.31, 0.29, 0.29
Tasks: 114 total,   1 running,  68 sleeping,   0 stopped,   0 zombie
%Cpu(s):  1.9 us,  0.1 sy,  0.0 ni, 98.0 id,  0.0 wa,  0.0 hi,  0.0 si,  0.0 st
KiB Mem :   949448 total,   153464 free,   223452 used,   572532 buff/cache
KiB Swap:  1331192 total,  1331192 free,        0 used.   412052 avail Mem

  PID USER      PR  NI    VIRT    RES    SHR S  %CPU %MEM     TIME+ COMMAND
 1215 pi        20   0  600844 325968 287276 S   5.3 34.3   8:09.51 chromium-browse
 2536 pi        20   0    8104   3204   2728 R   1.6  0.3   0:00.11 top
  970 pi        20   0  775108 156128 112876 S   1.0 16.4  11:17.06 chromium-browse
 1611 pi        20   0   11656   3772   3056 S   0.3  0.4   0:00.30 sshd
    1 root      20   0   27072   5964   4824 S   0.0  0.6   0:02.51 systemd
    2 root      20   0       0      0      0 S   0.0  0.0   0:00.00 kthreadd
    4 root       0 -20       0      0      0 I   0.0  0.0   0:00.00 kworker/0:0H
    6 root       0 -20       0      0      0 I   0.0  0.0   0:00.00 mm_percpu_wq
    7 root      20   0       0      0      0 S   0.0  0.0   0:00.24 ksoftirqd/0
    8 root      20   0       0      0      0 I   0.0  0.0   0:00.87 rcu_sched
    9 root      20   0       0      0      0 I   0.0  0.0   0:00.00 rcu_bh
```
### enable-ephemeral
```
pi@raspberrypi:~/zram-config $ df
Filesystem     1K-blocks    Used Available Use% Mounted on
devtmpfs          465976       0    465976   0% /dev
tmpfs              94832      48     94784   1% /mnt/run
/dev/mmcblk0p2  14803620 1280148  12889224  10% /ro
/dev/zram0        991512    5124    918804   1% /rw
overlayfs-root    991512    5124    918804   1% /
tmpfs             474152       0    474152   0% /dev/shm
tmpfs             474152    6356    467796   2% /run
tmpfs               5120       4      5116   1% /run/lock
tmpfs             474152       0    474152   0% /sys/fs/cgroup
/dev/mmcblk0p1     44220   30137     14083  69% /boot
tmpfs              94828       0     94828   0% /run/user/1000

```
```
pi@raspberrypi:~/zram-config $ zramctl
NAME       ALGORITHM DISKSIZE  DATA  COMPR TOTAL STREAMS MOUNTPOINT
/dev/zram0 lz4          1000M 19.2M 959.5K  1.4M       4 /rw
/dev/zram1 lz4           750M    4K    76B    4K       4 [SWAP]

```
### Performance
LZO/4 offer the best performance and for swaps they are probably the defacto choice.
You maybe have text based low impact directories such a /var/log /var/cache where highly
effective text compressors, such as deflate(zlib) & zstd are used in preference of disk size
and effective compression that can be up to 200% of what a LZ may achieve especially with text.
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
Check the tests in https://github.com/StuartIanNaylor/zram-config/tree/master/swap-performance for results.
### Uninstall
```
sudo sh /usr/local/share/zram-config/uninstall.sh
```


### Git Branches & Update
From the command line, enter `cd <path_to_local_repo>` so that you can enter commands for your repository.

Enter `git add --all` at the command line to add the files or changes to the repository.

Enter `git commit -m '<commit_message>'` at the command line to commit new files/changes to the local repository. For the <commit_message> , you can enter anything that describes the changes you are committing.

Enter `git push`  at the command line to copy your files from your local repository to remote.

Please feel free to clone, copy and hack, post idea, issues, join and support a community.

### Reference
https://www.kernel.org/doc/Documentation/blockdev/zram.txt
