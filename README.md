# zram-config
[![License](https://img.shields.io/github/license/ecdye/zram-config)](https://github.com/ecdye/zram-config/blob/main/LICENSE.md)
[![ShellCheck](https://github.com/ecdye/zram-config/workflows/ShellCheck/badge.svg)](https://github.com/ecdye/zram-config/actions?query=workflow%3AShellCheck)
[![Test](https://github.com/ecdye/zram-config/actions/workflows/test-action.yml/badge.svg)](https://github.com/ecdye/zram-config/actions/workflows/test-action.yml)

## Overview

This is a complete zram-config utility for swap, directories, and logs to reduce SD, NAND and eMMC block wear.
zram-config implements zram to prevent frequent writing to the disk and allow near ram speed access to working directories with varying compression ratios depending on the compression algorithm.

A ztab table in `/etc/ztab` is used to configure where any combination and number of zram drives are to be created.
This project uses an OverlayFS mount with zram so that syncFromDisk on start is not needed.
In theory this should allow for faster boots and larger directories as no complete directory copy is needed as it is the lower mount in the OverlayFS.
Many thanks go to [@kmxz](https://github.com/kmxz) for [kmxz/overlayfs-tools](https://github.com/kmxz/overlayfs-tools) which make this project possible.

The rationale for zram-config is that many distributions have `zram-config` packages that are actually broken, even by name, as often they are a zram-swap-config package in reality.
But even then they do not check for other zram services or change the parameters of swap from HD based configurations to ram optimized ones.
If all you are looking for is a zram-swap utility see [StuartIanNaylor/zram-swap-config](https://github.com/StuartIanNaylor/zram-swap-config).

Both [StuartIanNaylor/zram-swap-config](https://github.com/StuartIanNaylor/zram-swap-config) and [ecdye/zram-config](https://github.com/ecdye/zram-config) are great examples for distributions to get their zram packages updated.

Also if the OverlayFS guys would actually make some official merge/snapshot tools and not just leave it as just enough for Docker that would be massively useful, and if anyone fancies shouting out that call please do.

### COMPATIBILITY WARNING

The Raspberry Pi 4 8GB model can exhibit issues with zram due to a Linux kernel bug.
This bug has been fixed as of Raspberry Pi Kernel version 1.20210527.
See [raspberrypi/linux@cef3970381](https://github.com/raspberrypi/linux/commit/cef397038167ac15d085914493d6c86385773709) for more details about the issue.

## A Brief Usage Guide

### Table of Contents

1.  [Install](#install)
    -   [Manually start or stop](#manually-start-or-stop)
    -   [Sync files to disk](#sync-files-to-disk)
2.  [Update](#update)
3.  [Uninstall](#uninstall)
4.  [Configure](#customize)
    -   [Example configuration](#example-configuration)
5.  [Is it working?](#is-it-working)
6.  [Known issues](#known-issues)
    -   [Conflicts with services](#conflicts-with-services)
    -   [Swapiness on older Linux kernel versions](#swapiness-on-older-linux-kernel-versions)
7.  [Performance](#performance)
8.  [Reference](#reference)



### Install

``` shell
sudo apt-get install git
git clone https://github.com/ecdye/zram-config
sudo ./zram-config/install.bash
```

#### Manually start or stop

Use `sudo systemctl {start|stop} zram-config.service` to start or stop zram-config.
This will ensure that any changes are properly synced to the persistent storage before system poweroff.

#### Sync files to disk

Run `sudo zram-config sync` to sync any changes in the zram filesystems managed by zram-config to persistent storage.
If you have concerns about losing data due to sudden power loss you could use this to ensure that changes are synced to disk periodically.

A default sync service that will sync files to disk every night can be installed by running the following.

``` shell
sudo /path/to/zram-config/install.bash sync
```

Note that this sync service is not installed by default, you must install it separately.

### Update

``` shell
sudo /path/to/zram-config/update.bash
```

### Uninstall

``` shell
sudo /usr/local/share/zram-config/uninstall.bash
```

### Configure

All configuration is done in the `/etc/ztab` file.

Use `#` to comment out any line, add new drives with the first column providing the drive type and then drive details separated by tab characters.

All algorithms in `/proc/crypto` are supported but only `lzo-rle`, `lzo`, `lz4`, and `zstd` have zramctl text strings; `lzo-rle` is the fastest with `zstd` having much better text compression.

`mem_limit` is the compressed memory limit and will set a hard memory limit for the system admin.
Set to 0 to disable the `mem_limit`.

`disk_size` is the maximum size of the uncompressed memory.
It should be set to roughly 150% of `mem_limit` depending on the algorithm and how compressible the input files are.
Don't make it much higher than the compression algorithm (and the additional zram overhead) is capable of because there is a ~0.1% memory overhead when empty.

`swap_priority` will set zram over alternative swap devices.

`page-cluster` 0 means tuning to singular pages rather than the default 3 which caches 8 for HDD tuning, which can lower latency.

`swappiness` 150 because the improved performance of zram allows more usage without any adverse affects from the default of 60.
It can be raised up to 200 which will improve performance in high memory pressure situations.

`target_dir` is the directory you wish to hold in zram, and the original will be moved to a bind mount `bind_dir` and is synchronized on start, stop, and write commands.

`bind_dir` is the directory where the original directory will be mounted for sync purposes.
Usually in `/opt` or `/var`, name optional.

`oldlog_dir` will enable log-rotation to an off device directory while retaining only live logs in zram.
Usually in `/opt` or `/var`, name optional.

If you need multiple zram swaps or zram directories, just create another entry in `/etc/ztab`.
To do this simply add the new entries to the `/etc/ztab`, if you need to edit an active zram device you must stop zram with `sudo systemctl stop zram-config.service` and then edit any entries you need to.
Once finished, start zram using `sudo systemctl start zram-config.service` which will only add the new entries if zram is already running.

#### Example configuration

```
# swap	alg		mem_limit	disk_size	swap_priority	page-cluster	swappiness
swap	lzo-rle		250M		750M		75		0		150

# dir	alg		mem_limit	disk_size	target_dir		bind_dir
#dir	lzo-rle		50M		150M		/home/pi		/opt/zram/pi.bind

# log	alg		mem_limit	disk_size	target_dir		bind_dir		oldlog_dir
log	lzo-rle		50M		150M		/var/log		/opt/zram/log.bind	/opt/zram/oldlog
```

### Is it working?

Run `zramctl` in your preferred shell and if you see and output similar to below, yes it is working.

```
pi@raspberrypi:~$ zramctl
NAME       ALGORITHM DISKSIZE  DATA  COMPR TOTAL STREAMS MOUNTPOINT
/dev/zram1 lzo-rle       150M 16.9M 373.2K  692K       4 /opt/zram/zram1
/dev/zram0 lzo-rle       750M    4K    87B   12K       4 [SWAP]
```

To view more information on zram usage take a look at the following commands and their corresponding output.

```
pi@raspberrypi:~$ df
Filesystem     1K-blocks    Used Available Use% Mounted on
/dev/root        3833792 1368488   2275172  38% /
devtmpfs          437356       0    437356   0% /dev
tmpfs             471980       0    471980   0% /dev/shm
tmpfs             188792     440    188352   1% /run
tmpfs               5120       0      5120   0% /run/lock
/dev/mmcblk0p1    258095   49436    208660  20% /boot
/dev/zram1        132240   18440    103048  16% /opt/zram/zram1
overlay1          132240   18440    103048  16% /var/log
tmpfs              94396       0     94396   0% /run/user/1000
```
```
pi@raspberrypi:~$ free -h
               total        used        free      shared  buff/cache   available
Mem:           921Mi        46Mi       750Mi       0.0Ki       124Mi       819Mi
Swap:          849Mi          0B       849Mi
```
```
pi@raspberrypi:~$ swapon
NAME       TYPE      SIZE USED PRIO
/var/swap  file      100M   0B   -2
/dev/zram0 partition 750M   0B   75
```

### Known issues

#### Conflicts with services

When running zram on a directory that has services accessing it, they will need to be stopped before starting or stopping zram.
For example, in the log zram device zram-config stops the services that run by default in the `/var/log` directory before starting or stopping.
If your system has other services that write to `/var/log` that are not stopped zram may fail to properly sync files and remove the zram device when stopping, and will probably outright fail to start when initializing a zram device.
This issue is not limited to logs, if you are running zram on another directoy that is written to by a service you will run into the same issue.

For an example on how this project internally takes care of this issue see the `serviceConfiguration` function in zram-config.
A more in depth version of this function is used in the `openHAB` branch that can be referenced as well.

#### Swapiness on older Linux kernel versions

When running zram swap on Linux kernel versions older than 5.8 swappiness has a maximum value of 100.
If you observe issues runnning on older kernel versions try setting the default value of 150 back to 100.

### Performance

LZO-RLE offers the best performance and is probably the best choice, and from kernel 5.1 and onward it is the default.
If you are not running at least kernel 5.1 then LZO-RLE may not be supported by your system and you may need to change `/etc/ztab` accordingly.
You might have text based low impact directories such as `/var/log` or `/var/cache` where a highly effective text compressor such as zstd is optimal, with effective compression that can be up to 200% of what LZO may achieve especially with text.
With `/tmp` and `/run`, zram is unnecessary because they are RAM mounted as `tmpfs` and, if memory gets short, then the zram swap will provide extra.
It is only under intense loads that the slight overhead of zram compression becomes noticeable.

This chart from [facebook/zstd](https://github.com/facebook/zstd) provides a good benchmark for the performance of the different compressors.

| Compressor name  | Ratio | Compression| Decompress.|
|:-----------------|------:|-----------:|-----------:|
| zstd 1.5.1 -1    | 2.887 |   530 MB/s |  1700 MB/s |
| zlib 1.2.11 -1   | 2.743 |    95 MB/s |   400 MB/s |
| brotli 1.0.9 -0  | 2.702 |   395 MB/s |   450 MB/s |
| quicklz 1.5.0 -1 | 2.238 |   540 MB/s |   760 MB/s |
| lzo1x 2.10 -1    | 2.106 |   660 MB/s |   845 MB/s |
| lz4 1.9.3        | 2.101 |   740 MB/s |  4500 MB/s |
| lzf 3.6 -1       | 2.077 |   410 MB/s |   830 MB/s |
| snappy 1.1.9     | 2.073 |   550 MB/s |  1750 MB/s |

With swap, zram changes what is normally a static assumption that a HD is providing the swap using `swapiness` and `page-cache` where default `swapiness` is 60 and page-cache is 3.
Depending on the average load zram will benefit from a setting of 80-100 for `swapiness` and changing `page-cache` to 0 so that singular pages are written which will greatly reduce latency.
It is a shame `swapiness` is not dynamically based on load as for many systems there is often a huge difference in boot startup to settled load.
In some cases you may find you are reducing `swapiness` purely because of boot load.

### Reference

<https://www.kernel.org/doc/Documentation/blockdev/zram.txt>

<https://www.kernel.org/doc/Documentation/filesystems/overlayfs.txt>
