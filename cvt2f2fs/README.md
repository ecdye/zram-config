# cvt2f2fs

I copied this from https://www.raspberrypi.org/forums/viewtopic.php?p=1285848#p1285848 as have been trying to to a initramfs script
where I do the same but in a pivot mount live without need of USB.
Then noticed this script and thought well actually its just as valid.

It occured to me that with block wear you and that mostly we are running with SD cards with much spare space that 10-20% overprovision is
actually no big loss for many running specific applications.
So hey why not use this script and f2fs the flash friendly file system.

Script you have to hack slightly as it runs rpi-update and pulls in the kernel update for 4.19 which buster will reside on.
Buster is only a couple of month away but the biggest problem is that if the kernel version and f2fs version beome out of sync you will get errors.
You can log in via a normal sudo just do things in order and run
sudo cvt2f2fs
after reboot
sudo cvt2f2fs --phase2
after reboot
sudo cvt2f2fs --phase3
after reboot
sudo cvt2f2fs --phase4

So then you need to get f2fs-tools for buster as the script will run rpi-update.
sudo vi /etc/apt/sources.list.d/10-buster.list

deb http://mirrordirector.raspbian.org/raspbian/ buster main contrib non-free rpi

sudo vi /etc/apt/preferences.d/10-buster

Package: *
Pin: release n=stretch
Pin-Priority: 900

Package: *
Pin: release n=buster
Pin-Priority: 750

sudo apt-get update

Now we can grab things from buster when we want
sudo apt-get install -t buster f2fs-tools

You need to do the above as you will notice in syslog `fsck.f2fs: invalid option -- 'y'` 
Systemd seems to be trying to run with an invalid option
The above fixes that and fsck.f2fs will run and report everything is fine.
Thing is it will do that on every boot as the system thinks there is something wrong with the superblock.

I thought OK dunno why this script is doing an rpi-update anyway and I know there where a lot of f2fs commits in 4.18 but lets hack the
not to do the rpi-update bit.
Strangely you get the same syslog messages invalid option -- 'y'` as the initramfs fsck.f2fs fails as it would seem the tools & kernel
in stretch are not in version sync.
I presume that we have had kernel updates but not f2fs-tools updates.

Haven't done much more as f2fs was like I say an after thought that what is a huge over-provision of 10-20% is only approx 1-2gb
of a 8/16gb sd card that most of us use.
```
-o overprovision-ratio-percentage
              Specify the percentage over the volume size for overprovision area.  This  area  is
              hidden to users, and utilized by F2FS cleaner. The default percentage is 5%.
 ```
 simple as mkfs.f2fs -o 20 /dev/mmcblk0p2
 
 So included this here just for info as if you are using zram-conf other than just pure swaps then block and sd flash file systems might be of interest
 I will get round to solving the above probs but just thought I would shout out and ask.

Also there is one more thing that is confusing me 
```
-t nodiscard/discard
              Specify  1  or  0  to  enable/disable  discard policy.  If the value is equal to 1,
              discard policy is enabled, otherwise is disable.  The default value is 1.
```

f2fs has a optimised discard policy built in by default, but every example i see has an fstab or mount option with the discard directive set.
I keep thinking if it is inherant to the file system surely we don't use the discard method that say ext4 would use.
But it is confusing why with f2fs its specified at mkfs.f2fs -t 1 /dev/mmcblk0p2 and is the default.
Dunno it doesn't make sense to need mount or fstab discard entries when its already set on creation?
Or discard on mount or fstab will either use standard discard methods or if set via creation it will use the f2fs discard policy but you can turn that off by removing the mount or fstab discard option?

Anyone who uses f2fs please maybe explain as I will be adopting prob will wait for buster this summer but thought I would post and ask.
Its bugging me that there doesn't seem to be a clear rationale for this, or explanation anywhere.

