pub const config = @This();

const std = @import("std");
const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const linux = std.os.linux;
const log = std.log;
const SWAP_FLAG_PREFER = 0x8000;

allocator: Allocator,
arena: *ArenaAllocator,

pub fn init(allocator: Allocator) !config {
    const arena = try allocator.create(ArenaAllocator);
    arena.* = ArenaAllocator.init(allocator);
    const alloc = arena.allocator();

    const self = try alloc.create(config);
    self.* = config{ .allocator = allocator, .arena = arena };

    return self.*;
}

pub fn deinit(self: *config) void {
    self.arena.deinit();
    self.allocator.destroy(self.arena);
}

pub fn zswap(
    self: *config,
    dev: i8,
    priority: u8,
    page_cluster: ?[]const u8,
    swappiness: ?[]const u8,
) !void {
    const alloc = self.arena.allocator();
    const dev_p = try std.fmt.allocPrintZ(alloc, "/dev/zram{d}", .{dev});
    defer alloc.free(dev_p);

    const label = try std.fmt.allocPrint(alloc, "zram-config{d}", .{dev});
    defer alloc.free(label);

    // TODO: Do this manually without calling mkswap
    const mkswap = [_][]const u8{ "mkswap", "--label", label, dev_p };
    var proc = std.process.Child.init(&mkswap, alloc);
    proc.stdin_behavior = .Ignore;
    proc.stdout_behavior = .Ignore;
    proc.stderr_behavior = .Ignore;
    const r1 = try proc.spawnAndWait();
    if (r1 != .Exited) {
        log.err("failed to mkswap: {s}", .{@tagName(r1)});
        return error.MkSwap;
    }

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

pub fn rm_zswap(self: *config, dev: i8) !void {
    const alloc = self.arena.allocator();
    const dev_p = try std.fmt.allocPrintZ(alloc, "/dev/zram{d}", .{dev});
    defer alloc.free(dev_p);

    const r1 = linux.E.init(linux.syscall1(.swapoff, @intFromPtr(dev_p.ptr)));
    if (r1 != .SUCCESS) {
        log.err("failed to swapoff: {s}", .{@tagName(r1)});
        return error.SysSwapoff;
    }
}
