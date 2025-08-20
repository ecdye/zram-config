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

pub fn zdir(dev: i8, target_dir: []const u8, bind_dir: []const u8) !void {
    var zdir_p = std.fs.openDirAbsolute(ZRAM_DIR, .{}) catch blk: {
        try std.fs.makeDirAbsolute(ZRAM_DIR);
        break :blk try std.fs.openDirAbsolute(ZRAM_DIR, .{});
    };
    defer zdir_p.close();

    var buf: [6]u8 = undefined;
    const target_d_p = try std.fmt.bufPrint(&buf, "zram{d}", .{dev});
    try zdir_p.makePath(target_d_p);

    var target_d = try std.fs.openDirAbsolute(target_dir, .{});
    defer target_d.close();
    const dir_stat = try target_d.stat();
    const dir_perm = dir_stat.mode & 0o777;

    log.debug("target directory permissions: {o:03}, bind: {s}", .{ dir_perm, bind_dir });
}

