# Swap-performance
Using a raspbian lite / zram-config and https://github.com/StuartIanNaylor/MagicMirror-Install-Guide-Raspberry-0-to-3
with mirrorcomplex and plymouth pretty.

15 min boots logging /proc/loadavg every 2 secs stored in a spreadsheet with the average of 3 datasets looking at:-
1st 30 seconds
1st Minute
1st 2 minutes
Overall load
Last 2 minutes
Last minute

Really it needs far more datasets to be authorative but provides an approx reflections

_____

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
https://github.com/StuartIanNaylor/zram-swap-config/tree/Swapiness-load-balancer has a branch with a crude
dynamic swapiness load balancer as reduction in swapiness can help intense load period but lose when load
is less.
Currently there is a LibreOffice spreadsheet for a Pi-3B(2015) and will also add Pi-Zero & Pi-3B+ tests later.
