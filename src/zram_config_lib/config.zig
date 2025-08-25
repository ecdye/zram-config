pub const config = @This();

const std = @import("std");
const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const linux = std.os.linux;
const log = std.log;
const helpers = @import("helpers.zig");

const SWAP_FLAG_PREFER = 0x8000;
const BLKGETSIZE64 = 0x80081272;
const ZRAM_DIR = "/opt/zram";

const SwapHeader = struct {
    version: u32 = 1,
    last_page: i32,
    nr_badpages: u32 = 0,
    uuid: [16]u8,
    volume_name: [16]u8,
    _padding: [4098 - 1080]u8 = [_]u8{0} ** (4098 - 1080),
    magic: [10]u8 = [_]u8{ 'S', 'W', 'A', 'P', 'S', 'P', 'A', 'C', 'E', '2' },

    pub fn write(self: *const SwapHeader, file: std.fs.File) !void {
        const bytes = std.mem.asBytes(self);
        _ = try file.pwriteAll(bytes, 0x400);
    }
};

pub fn zswap(
    dev: i8,
    priority: u8,
    page_cluster: ?[]const u8,
    swappiness: ?[]const u8,
) !void {
    var buf: [16]u8 = undefined;
    const dev_p = try std.fmt.bufPrintZ(&buf, "/dev/zram{d}", .{dev});

    var label: [16]u8 = [_]u8{0} ** 16;
    _ = try std.fmt.bufPrint(&label, "zram-config{d}", .{dev});

    const dev_f = try std.fs.openFileAbsolute(dev_p, .{ .mode = .read_write });
    var size: u64 = 0;
    _ = linux.ioctl(dev_f.handle, BLKGETSIZE64, @intFromPtr(&size));
    const header = SwapHeader{
        .last_page = @intCast((size / 4096) - 1),
        .uuid = helpers.make_uuid_v4(),
        .volume_name = label,
    };
    try header.write(dev_f);

    const flags = SWAP_FLAG_PREFER | @as(usize, priority);
    const r2 = linux.E.init(linux.syscall2(.swapon, @intFromPtr(dev_p.ptr), flags));
    if (r2 != .SUCCESS) {
        log.err("failed to swapon: {s}", .{@tagName(r2)});
        return error.SysSwapon;
    }

    if (page_cluster) |cluster| {
        const cluster_f = try std.fs.openFileAbsolute(
            "/proc/sys/vm/page-cluster",
            .{ .mode = .write_only },
        );
        defer cluster_f.close();
        try cluster_f.writeAll(cluster);
    }

    if (swappiness) |swness| {
        const swness_f = try std.fs.openFileAbsolute(
            "/proc/sys/vm/swappiness",
            .{ .mode = .write_only },
        );
        defer swness_f.close();
        try swness_f.writeAll(swness);
    }
}

pub fn rm_zswap(dev: i8) !void {
    var buf: [16]u8 = undefined;
    const dev_p = try std.fmt.bufPrintZ(&buf, "/dev/zram{d}", .{dev});

    const r1 = linux.E.init(linux.syscall1(.swapoff, @intFromPtr(dev_p.ptr)));
    if (r1 != .SUCCESS) {
        log.err("failed to swapoff: {s}", .{@tagName(r1)});
        return error.SysSwapoff;
    }
}

pub fn zdir(
    alloc: Allocator,
    dev: i8,
    target_dir: [:0]const u8,
    bind_dir: []const u8,
    oldlog_dir: ?[]const u8,
) !void {
    var zdir_p = std.fs.openDirAbsolute(ZRAM_DIR, .{}) catch blk: {
        try std.fs.makeDirAbsolute(ZRAM_DIR);
        break :blk try std.fs.openDirAbsolute(ZRAM_DIR, .{});
    };
    defer zdir_p.close();

    var buf: [6]u8 = undefined;
    const target_d_p = try std.fmt.bufPrintZ(&buf, "zram{d}", .{dev});
    try zdir_p.makePath(target_d_p);
    try zdir_p.makePath(bind_dir);

    var target_d = try std.fs.openDirAbsoluteZ(target_dir, .{});
    defer target_d.close();

    var stat_buf: linux.Statx = undefined;
    _ = linux.statx(target_d.fd, target_dir, linux.AT.SYMLINK_NOFOLLOW, linux.STATX_BASIC_STATS, &stat_buf);

    const dir_perm = stat_buf.mode & stat_buf.mask;
    const dir_user = stat_buf.uid;
    const dir_group = stat_buf.gid;

    log.debug("target directory permissions: {o:03} {d}:{d}, bind: {s}", .{
        dir_perm,
        dir_user,
        dir_group,
        bind_dir,
    });
    const bind_d = try std.fmt.allocPrintSentinel(alloc, "{s}/{s}", .{ ZRAM_DIR, bind_dir }, 0);
    defer alloc.free(bind_d);
    log.info("mounting: {s}, {s}", .{ target_dir, bind_d });

    helpers.mount_or_error(
        target_dir.ptr,
        bind_d.ptr,
        null,
        linux.MS.BIND,
        @intFromPtr("".ptr),
    ) catch |err| {
        log.err("failed to mount bind: {t}", .{err});
        return err;
    };
    errdefer helpers.umount_or_error(target_dir.ptr, linux.MNT.FORCE) catch |err| {
        log.err("failed to cleanup bind mount: {t}", .{err});
    };
    helpers.mount_or_error(
        "".ptr,
        bind_d.ptr,
        null,
        linux.MS.PRIVATE,
        @intFromPtr("".ptr),
    ) catch |err| {
        log.err("failed to make bind private: {t}", .{err});
        return err;
    };
    var dir_settings = try dir_opts(alloc, bind_d);
    defer dir_settings.deinit(alloc);

    const mkfs = try std.fmt.allocPrint(alloc, "mkfs.{s}", .{dir_settings.fstype});
    defer alloc.free(mkfs);

    var dev_p_buf: [16]u8 = undefined;
    const dev_p = try std.fmt.bufPrintZ(&dev_p_buf, "/dev/zram{d}", .{dev});
    var child = std.process.Child.init(&[_][]const u8{ mkfs, dev_p }, alloc);
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    const res = try child.spawnAndWait();
    if (res.Exited != 0) {
        log.err("failed to mkfs on {s}: {d}", .{ dev_p, res.Exited });
    }

    const target_d_p_f = try std.fmt.allocPrintSentinel(alloc, "{s}/{s}", .{ ZRAM_DIR, target_d_p }, 0);
    defer alloc.free(target_d_p_f);
    const options = try parse_mnt_opts(alloc, dir_settings.options);
    helpers.mount_or_error(
        dev_p.ptr,
        target_d_p_f.ptr,
        dir_settings.fstype.ptr,
        options.flags,
        @intFromPtr(options.data.ptr),
    ) catch |err| {
        log.err("failed to mount zram device: {t}", .{err});
        return err;
    };
    errdefer helpers.umount_or_error(dev_p.ptr, linux.MNT.FORCE) catch |err| {
        log.err("failed to cleanup zram device mount: {t}", .{err});
    };

    const upper = try std.fmt.allocPrintSentinel(alloc, "{s}/upper", .{target_d_p_f}, 0);
    defer alloc.free(upper);
    const workdir = try std.fmt.allocPrintSentinel(alloc, "{s}/workdir", .{target_d_p_f}, 0);
    defer alloc.free(workdir);
    try std.fs.makeDirAbsoluteZ(upper);
    try std.fs.makeDirAbsoluteZ(workdir);

    const overlay = try std.fmt.allocPrintSentinel(alloc, "overlay{d}", .{dev}, 0);
    defer alloc.free(overlay);
    const options_overlay = try std.fmt.allocPrintSentinel(
        alloc,
        "redirect_dir=on,metacopy=on,lowerdir={s},upperdir={s},workdir={s}",
        .{ bind_d, upper, workdir },
        0,
    );

    helpers.mount_or_error(
        overlay.ptr,
        target_dir.ptr,
        "overlay",
        0,
        @intFromPtr(options_overlay.ptr),
    ) catch |err| {
        log.err("failed to mount overlay: {t}", .{err});
        return err;
    };
    errdefer helpers.umount_or_error(overlay.ptr, linux.MNT.FORCE) catch |err| {
        log.err("failed to clean up overlay mount: {t}", .{err});
    };

    var o_dir = try std.fs.openDirAbsoluteZ(target_d_p_f, .{ .iterate = true });
    defer o_dir.close();
    var upper_d = try o_dir.openDir("upper", .{ .iterate = true });
    defer upper_d.close();
    try upper_d.chown(dir_user, dir_group);
    try upper_d.chmod(dir_perm);
    var workdir_d = try o_dir.openDir("workdir", .{ .iterate = true });
    defer workdir_d.close();
    try workdir_d.chown(dir_user, dir_group);
    try workdir_d.chmod(dir_perm);

    if (oldlog_dir) |oldlog| {
        var ol_f = try std.fs.createFileAbsolute("/etc/logrotate.d/00_oldlog", .{});
        const setup = try std.fmt.allocPrint(alloc,
            \\ oldlog {s}
            \\ createolddir 755 root root
            \\ renamecopy
        , .{oldlog});
        defer alloc.free(setup);
        try ol_f.writeAll(setup);
    }
}

fn parse_mnt_opts(alloc: Allocator, opts: []const u8) !struct { flags: u32, data: [:0]const u8 } {
    var flags: u32 = 0;
    var extra = std.ArrayList(u8){};
    defer extra.deinit(alloc);

    var it = std.mem.splitScalar(u8, opts, ',');
    while (it.next()) |opt| {
        const o = std.mem.trim(u8, opt, " \t");

        if (std.mem.eql(u8, o, "ro")) {
            flags |= linux.MS.RDONLY;
        } else if (std.mem.eql(u8, o, "rw")) {
            // no flag; default is rw
        } else if (std.mem.eql(u8, o, "relatime")) {
            flags |= linux.MS.RELATIME;
        } else if (std.mem.eql(u8, o, "noexec")) {
            flags |= linux.MS.NOEXEC;
        } else if (std.mem.eql(u8, o, "nosuid")) {
            flags |= linux.MS.NOSUID;
        } else {
            if (extra.items.len > 0) try extra.append(alloc, ',');
            try extra.appendSlice(alloc, o);
        }
    }

    return .{
        .flags = flags,
        .data = try extra.toOwnedSliceSentinel(alloc, 0),
    };
}

const DirOpts = struct {
    options: []u8,
    fstype: [:0]u8,

    pub fn deinit(self: *DirOpts, alloc: Allocator) void {
        alloc.free(self.options);
        alloc.free(self.fstype);
    }
};

fn dir_opts(alloc: Allocator, bind_dir: [:0]const u8) !DirOpts {
    var mounts = try std.fs.openFileAbsoluteZ("/proc/mounts", .{});
    defer mounts.close();

    var line_buf: [4096]u8 = undefined;
    var mounts_r = mounts.reader(&line_buf);
    while (mounts_r.interface.takeDelimiterExclusive('\n')) |line| {
        var tokens = std.mem.tokenizeAny(u8, line, " \t");

        const device = tokens.next() orelse continue;
        const mountpoint = tokens.next() orelse continue;
        const fstype = tokens.next() orelse continue;
        const options = tokens.next() orelse continue;

        if (std.mem.eql(u8, mountpoint, bind_dir)) {
            log.info("dev: {s}, fstype: {s}, options: {s}", .{ device, fstype, options });
            return DirOpts{
                .options = try alloc.dupe(u8, options),
                .fstype = try alloc.dupeZ(u8, fstype),
            };
        }
    } else |err| switch (err) {
        error.EndOfStream, // stream ended not on a line break
        error.StreamTooLong, // line could not fit in buffer
        error.ReadFailed, // caller can check reader implementation for diagnostics
        => |e| return e,
    }
}

fn merge_overlay(alloc: Allocator, lower: []const u8, upper: []const u8) !void {
    const lower_opt = try std.fmt.allocPrintSentinel(alloc, "--lowerdir={s}", .{lower}, 0);
    defer alloc.free(lower_opt);
    const upper_opt = try std.fmt.allocPrintSentinel(alloc, "--upperdir={s}/upper", .{upper}, 0);
    defer alloc.free(upper_opt);

    var child = std.process.Child.init(&[_][]const u8{
        "overlay",
        "merge",
        "--force-execution",
        "--ignore-mounted",
        lower_opt,
        upper_opt,
    }, alloc);
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    const res = try child.spawnAndWait();
    if (res.Exited != 0) {
        log.err("failed to merge overly {s}: {d}", .{ lower, res.Exited });
    }
}

pub fn rm_zdir(alloc: Allocator, dev: i8, bind_dir: []const u8, target_dir: []const u8) !void {
    log.info("removing target: {s}", .{target_dir});
    const target_d = try std.fmt.allocPrintSentinel(alloc, "{s}", .{target_dir}, 0);
    defer alloc.free(target_d);
    helpers.umount_or_error(target_d.ptr, linux.MNT.DETACH) catch |err| {
        log.err("failed to umount overlay, attempting to continue: {t}", .{err});
    };

    const bind_d = try std.fmt.allocPrintSentinel(alloc, "{s}/{s}", .{ ZRAM_DIR, bind_dir }, 0);
    defer alloc.free(bind_d);
    var buf: [6]u8 = undefined;
    const target_d_p = try std.fmt.bufPrint(&buf, "zram{d}", .{dev});
    const target_d_p_f = try std.fmt.allocPrintSentinel(alloc, "{s}/{s}", .{ ZRAM_DIR, target_d_p }, 0);
    defer alloc.free(target_d_p_f);

    try merge_overlay(alloc, bind_d, target_d_p_f);

    helpers.umount_or_error(target_d_p_f.ptr, linux.MNT.DETACH) catch |err| {
        log.err("failed to umount zram target mount: {t}", .{err});
    };
    helpers.umount_or_error(bind_d.ptr, linux.MNT.DETACH) catch |err| {
        log.err("failed to umount bind: {t}", .{err});
    };

    var zdir_p = std.fs.openDirAbsolute(ZRAM_DIR, .{}) catch blk: {
        try std.fs.makeDirAbsolute(ZRAM_DIR);
        break :blk try std.fs.openDirAbsolute(ZRAM_DIR, .{});
    };
    defer zdir_p.close();

    try zdir_p.deleteTree(target_d_p);
    try zdir_p.deleteTree(bind_dir);
    std.fs.deleteFileAbsolute("/etc/logrotate.d/00_oldlog") catch |err| {
        switch (err) {
            error.FileNotFound => return,
            else => return err,
        }
    };
}
