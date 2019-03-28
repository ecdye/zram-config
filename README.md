# zram-config
Complete zram config utility for swap, directory &amp; log 
Usefull for IoT / maker projects for reducing SD, Nand and Emmc block wear via log operations.
Uses Zram to minimise precious memory footprint and extremely infrequent write outs.

Uses a ztab table in /etc/ztab where any combination and number of zram drives can be created.

_____
## Menu
1. [Install](#install)
2. [Config](#config)
3. [It is working ?](#it-is-working)
4. [Uninstall](#uninstall-)

## Install
    sudo apt-get install git
    git clone https://github.com/StuartIanNaylor/zram-config
    cd zram-config
    sudo sh install.sh
    

## Customize
In the file `/etc/ztab` `sudo nano /etc/ztab` to edit:
`#` To comment out any line
Add new drives with the first collumn providing the drive type and then drive details seperated by tab
All algorithm in /proc/crypto are supported but only lzo/lz4 have zramctl text strings.
lz4 is the fastest whilst deflate as much better text compression.
mem_limit is compressed memory limit and will is a hard memory limit for sys admin.
disk_size is virtual uncompressed size approx 220-450% depending on algorithm and input file
swap_priority set zram over alternative swap devices
page-cluster 0 means tuning to singular pages rather than default 3 which caches 8 for HDD tuning
swappiness 80 due to improved performance of zram allows more usage without effect of rainsing from default 60
zram_dir is the directory you wish to hold in zram, the original is moved to a bind mount bind_dir and is synchronised on start/stop and write commands.
bind_dir is a directory where the orinal die will be mounted for sync purposes.
oldlog_dir will enable logrotation to an off device directory whilst retaining only live logs in zram
If you need multiple zram swaps or zram dirs just create another entry in /ect/ztab
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
sudo /usr/local/bin/zram-config write
…
This will write out any updated files to persistant storage, usefull for new installs without need for start/stop or reboot
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


## Uninstall
```
sudo sh /usr/local/share/zramdrive/uninstall.sh
```


## Git Branches & Update
From the command line, enter `cd <path_to_local_repo>` so that you can enter commands for your repository.
Enter `git add --all` at the command line to add the files or changes to the repository
Enter `git commit -m '<commit_message>'` at the command line to commit new files/changes to the local repository. For the <commit_message> , you can enter anything that describes the changes you are committing.
Enter `git push`  at the command line to copy your files from your local repository to remote.
