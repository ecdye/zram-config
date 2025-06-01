pub const zram = @This();

const std = @import("std");
const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const log = std.log;
const linux = std.os.linux;
const zstd = std.compress.zstd;
const helpers = @import("helpers.zig");

allocator: Allocator,
arena: *ArenaAllocator,
loaded: bool = false,

pub fn init(allocator: Allocator) !zram {
    const arena = try allocator.create(ArenaAllocator);
    arena.* = ArenaAllocator.init(allocator);
    const alloc = arena.allocator();

    const self = try alloc.create(zram);
    self.* = zram{ .allocator = allocator, .arena = arena };

    return self.*;
}

pub fn deinit(self: *zram) void {
    self.arena.deinit();
    self.allocator.destroy(self.arena);
}

pub fn load_module(self: *zram) !?i8 {
    const alloc = self.arena.allocator();

    const maybe_z = std.fs.openDirAbsolute("/sys/module/zram", .{}) catch null;
    if (maybe_z) |const_z| {
        var z = const_z;
        z.close();
        self.loaded = true;
        log.debug("zram already loaded", .{});
        return null;
    }

    const Utsname = extern struct {
        sysname: [65]u8,
        nodename: [65]u8,
        release: [65]u8,
        version: [65]u8,
        machine: [65]u8,
        domainname: [65]u8,
    };

    var uts: Utsname = undefined;
    const r1 = linux.E.init(linux.syscall1(.uname, @intFromPtr(&uts)));
    if (r1 != .SUCCESS) {
        log.err("failed to get uname: {s}", .{@tagName(r1)});
        return error.GetUname;
    }
    const release = std.mem.sliceTo(&uts.release, 0);

    const module_path = try std.fmt.allocPrint(
        alloc,
        "/lib/modules/{s}/kernel/drivers/block/zram/zram.ko.zst",
        .{release},
    );
    defer alloc.free(module_path);

    const module = try std.fs.openFileAbsolute(module_path, .{});
    defer module.close();
    const bufc_size = try module.getEndPos();
    const bufc = try module.readToEndAlloc(alloc, bufc_size);
    defer alloc.free(bufc);

    var stream = std.io.fixedBufferStream(bufc);
    const header = try zstd.decompress.decodeFrameHeader(stream.reader());
    const bufd_s = header.zstandard.content_size orelse return error.HeaderContentSize;

    const bufd = try alloc.alloc(u8, @intCast(bufd_s));
    _ = try zstd.decompress.decode(bufd, bufc, false);
    defer alloc.free(bufd);

    const r2 = linux.E.init(linux.syscall3(
        .init_module,
        @intFromPtr(bufd.ptr),
        bufd.len,
        @intFromPtr("".ptr),
    ));
    if (r2 != .SUCCESS) {
        log.err("failed to init_module: {s}", .{@tagName(r2)});
        return error.InitModule;
    }

    log.debug("loaded zram module successfully", .{});
    self.loaded = true;
    return 0;
}

pub fn add_device(self: *zram) !i8 {
    const alloc = self.arena.allocator();
    while (!self.loaded) {
        const dev_n = try self.load_module() orelse break;
        return dev_n;
    }

    const hot_add = try std.fs.openFileAbsolute("/sys/class/zram-control/hot_add", .{});
    defer hot_add.close();

    const buf = try hot_add.readToEndAlloc(alloc, 8);
    defer alloc.free(buf);

    const dev = std.mem.trimRight(u8, buf, "\n");
    return try std.fmt.parseInt(i8, dev, 10);
}

pub fn config_device(
    self: *zram,
    dev: i8,
    alg: []const u8,
    disk_s: []const u8,
    mem_l: []const u8,
) !void {
    const alloc = self.arena.allocator();
    try helpers.zblock_config_write(alloc, dev, "comp_algorithm", alg);
    try helpers.zblock_config_write(alloc, dev, "disksize", disk_s);
    try helpers.zblock_config_write(alloc, dev, "mem_limit", mem_l);
    if (std.mem.eql(u8, mem_l, "0")) log.info("no memory limit set for /dev/zram{d}", .{dev});
}

/// Abstracts `add_device()` and `config_device()` into a single function that
/// performs both adding a new zram device and configuring its options in a
/// single function.
///
/// On success, returns device number of the added and configured zram device.
pub fn add_config_device(
    self: *zram,
    alg: []const u8,
    disk_s: []const u8,
    mem_l: []const u8,
) !i8 {
    const dev = try self.add_device();
    try self.config_device(dev, alg, disk_s, mem_l);
    return dev;
}

pub fn remove_device(self: *zram, dev: i8) !void {
    const alloc = self.arena.allocator();
    try helpers.zblock_config_write(alloc, dev, "reset", "1");

    const hot_remove = try std.fs.openFileAbsolute(
        "/sys/class/zram-control/hot_remove",
        .{ .mode = .write_only },
    );
    defer hot_remove.close();

    const dev_s = try std.fmt.allocPrint(alloc, "{d}", .{dev});
    defer alloc.free(dev_s);
    _ = try hot_remove.write(dev_s);
}
