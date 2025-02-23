---
title: zram-config
section: 1
header: zram-config
date: February 2025
---

# NAME

zram-config - A complete utility for swap, directories, and logs to reduce SD, NAND and eMMC block wear

# SYNOPSIS

**zram-config** {start|stop|sync}

# DESCRIPTION

**zram-config** is a utility for swap, directories, and logs to reduce SD, NAND and eMMC block wear. Furthermore zram
allows near RAM speed access to working directories, and prevents frequent writing to persistent storage. Even more
importantly, data stored in zram can be compressed to conserve memory.

**zram-config** is configured by a table located at `/etc/ztab` is used to configure any number and type of zram
devices. Using the table a zram device is configured and mounted to an OverlayFS filesystem as the upper filesystem.
OverlayFS is used so that files do not need to be copied from persistent storage to RAM on startup. In theory this
should allow for faster boots and larger directories as no complete directory copy is needed.

As a general rule, be sure that any services that are using configured zram devices are stopped before running
zram-config.

Because all configuration is performed in the table at `/etc/ztab` the only commands accepted are as follows:

## *start*

Starts up zram as configured in `/etc/zram`. If the table has been edited since the zram was last started, only the
newly configured devices will be started.

## *stop*

Stops any running devices configured by zram-config and syncs the changes back to persistent storage.

## *sync*

Syncs any changes back to persistent storage. This ensures no data will be lost in the case of sudden power loss.

# OPTIONS

All options are configured in `/etc/ztab`. The format for `/etc/ztab` is one device configuration per line with each
option separated by a tab character. The device can be one of `swap`, `dir`, or `log`. There is little difference
between `dir` and `log` except that `log` has additional options for log rotation. A `#` can be used at the start of any
line to comment it out.

To add additional devices, just add additional entries in `/etc/ztab`. To edit an active device, you must stop
zram-config and then edit any entries. Once any edits are complete start zram-config for the changes to take effect.

## *alg*

All algorithms in `/proc/crypto` are supported but only `lzo-rle`, `lzo`, `lz4`, and `zstd` have zramctl text strings;
`lzo-rle` is the fastest with `zstd` having much better text compression.

## *mem_limit*

The compressed memory limit and will set a hard memory limit for the system admin. Set to 0 to disable the `mem_limit`.

## *disk_size*

The maximum size of the uncompressed memory. It should be set to roughly 150% of `mem_limit` depending on the algorithm
and how compressible the input files are. Don't make it much higher than the compression algorithm (and the additional
zram overhead) is capable of because there is a ~0.1% memory overhead when empty.

## *swap_priority*

Can be used to set zram at a higher priority over alternative swap devices.

## *page-cluster*

Tune swap pages for performance, 0 means tuning to singular pages rather than the default 3 which caches 8 for HDD
tuning, which can lower latency.

## *swappiness*

Tune how aggressively the kernel will swap pages, zram-config defaults to 150 because the improved performance of zram
allows more usage without any adverse affects from the system default of 60. It can be raised up to 200 which will
improve performance in high memory pressure situations.

## *target_dir*

The directory you wish to hold in zram, and the original will be moved to an OverlayFS bind mount and is synchronized on
start, stop, and sync commands.

## *oldlog_dir*

Used to enable log-rotation to an off zram directory while retaining only live logs in zram. Usually in `/opt` or
`/var`, configuration is optional.

# REPORTING BUGS

For bug reports, use the issue tracker at <https://github.com/ecdye/zram-config/issues>.

# SEE ALSO

zramctl(8)

Kernel references:

- <https://www.kernel.org/doc/Documentation/blockdev/zram.txt>
- <https://www.kernel.org/doc/Documentation/filesystems/overlayfs.txt>
