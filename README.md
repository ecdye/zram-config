# zram-config
[![License](https://img.shields.io/github/license/ecdye/zram-config)](https://github.com/ecdye/zram-config/blob/main/LICENSE.md)
[![ShellCheck](https://github.com/ecdye/zram-config/workflows/ShellCheck/badge.svg)](https://github.com/ecdye/zram-config/actions?query=workflow%3AShellCheck)
[![Test](https://github.com/ecdye/zram-config/actions/workflows/test-action.yml/badge.svg)](https://github.com/ecdye/zram-config/actions/workflows/test-action.yml)

## Overview

This is a complete zram-config utility for swap, directories, and logs to reduce SD, NAND and eMMC block wear.
Furthermore zram allows near RAM speed access to working directories, and prevents frequent writing to persistent storage.
Even more importantly, data stored in zram can be compressed to conserve memory.

A table located at `/etc/ztab` is used to configure any number and type of zram devices.
Using the table an OverlayFS mount is used to mount the newly created zram device as the upper filesystem of the OverlayFS.
OverlayFS is used so that files do not need to be copied from persistent storage to RAM on startup.
In theory this should allow for faster boots and larger directories as no complete directory copy is needed.
A version of [kmxz/overlayfs-tools](https://github.com/kmxz/overlayfs-tools) is used to implement the OverlayFS sync logic.

This tool is primarily developed and tested against Raspberry Pi OS.
Any Debian derivative should also work out of the box, however there is no guarantee.
Experimental Alpine support has also been added, other distributions may work but once again, there is no guarantee.

## A Brief Usage Guide

### Install

The following assumes that you have the [`gh`](https://cli.github.com) cli tool installed and setup on your system.

``` shell
gh release download --repo ecdye/zram-config --pattern '*.tar.lz'
mkdir -p zram-config && tar -xf zram-config*.tar.lz --strip-components=1 --directory=zram-config
sudo ./zram-config/install.bash
```

#### Manually start or stop

On Debian, use `sudo systemctl {start|stop} zram-config.service` to start or stop zram-config.
On Alpine, use `sudo rc-service zram-config {start|stop}`.
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

To make changes to the code or checkout a specific branch/tag and prevent it from updating/resetting all changes run the following instead.

``` shell
sudo /path/to/zram-config/update.bash custom
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

`target_dir` is the directory you wish to hold in zram, and the original will be moved to a bind mount and is synchronized on start, stop, and write commands.

`oldlog_dir` will enable log-rotation to an off device directory while retaining only live logs in zram.
Usually in `/opt` or `/var`, name optional.

If you need multiple zram swaps or zram directories, just create another entry in `/etc/ztab`.
To do this simply add the new entries to the `/etc/ztab`, if you need to edit an active zram device you must stop zram with `sudo systemctl stop zram-config.service` on Debian or `sudo rc-service zram-config stop` on Alpine and then edit any entries you need to.
Once finished, start zram using `sudo systemctl start zram-config.service` or `sudo rc-service zram-config start` which will only add the new entries if zram is already running.

#### Example configuration

```
# swap	alg		mem_limit	disk_size	swap_priority	page-cluster	swappiness
swap	lzo-rle		250M		750M		75		0		150

# dir	alg		mem_limit	disk_size	target_dir
#dir	lzo-rle		50M		150M		/home/pi

# log	alg		mem_limit	disk_size	target_dir	oldlog_dir
log	lzo-rle		50M		150M		/var/log	/opt/zram/oldlog
```

### Is it working?

Run `zramctl` in your preferred shell and if you see and output similar to below, yes it is working.
Please note that if the `zramctl` command is missing, you will need to install the `util-linux` package to have a convenient way to view the zram status.

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

#### Raspberry Pi 4 8GB compatibility

The Raspberry Pi 4 8GB model can exhibit issues with zram due to a Linux kernel bug.
This bug has been fixed as of Raspberry Pi Kernel version 1.20210527.
See [raspberrypi/linux@cef3970381](https://github.com/raspberrypi/linux/commit/cef397038167ac15d085914493d6c86385773709) for more details about the issue.

#### Filesystem compatibility

By default zram-config should support most regular filesystems, as long as the tools are installed and available on the host system.
In some cases, with niche filesystems some manual editing of the code may be required to enable support.

Pull requests adding support for filesystems that don't work automatically are welcome.

#### Compatibility issues in virtual machines

When running zram-config in a virtual machine (VM), you may encounter compatibility issues due to the differences in how VMs handle memory and storage compared to physical hardware.
Performance may vary, and certain features might not work as expected.
It is also common for VMs to not have implemented emulation in their kernel for zram.
If you experience issues, it may be better to not use zram-config in your VM environment.
It is recommended to thoroughly test zram-config in your specific VM setup to ensure it meets your needs.

#### Removal of `bind_dir` in `ztab`

Older versions of zram-config included the option to manually configure a `bind_dir` in the `ztab`.
This functionality was removed in favor of automatically creating a bind mount as it is less confusing and more consistent with the rest of the code.

Checks are in place to automatically convert `ztab` to this new format.
If errors occur, you may need to manually edit `ztab` to fix any issues.

### Performance

LZO-RLE offers the best performance and is probably the best choice, and from kernel 5.1 and onward it is the default.
If you are not running at least kernel 5.1 then LZO-RLE may not be supported by your system and you may need to change `/etc/ztab` accordingly.
You might have text based low impact directories such as `/var/log` or `/var/cache` where a highly effective text compressor such as zstd is optimal, with effective compression that can be up to 200% of what LZO may achieve especially with text.
With `/tmp` and `/run`, zram is unnecessary because they are RAM mounted as `tmpfs` and, if memory gets short, then the zram swap will provide extra.
It is only under intense loads that the slight overhead of zram compression becomes noticeable.

This chart in [facebook/zstd](https://github.com/facebook/zstd?tab=readme-ov-file#benchmarks) provides a good reference for the performance of the different compressors.

### Reference

<https://www.kernel.org/doc/Documentation/blockdev/zram.txt>

<https://www.kernel.org/doc/Documentation/filesystems/overlayfs.txt>
