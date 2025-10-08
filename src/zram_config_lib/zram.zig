pub const zram = @This();

const std = @import("std");
const mem = std.mem;
const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = mem.Allocator;
const log = std.log;
const linux = std.os.linux;
const helpers = @import("helpers.zig");

arena: *ArenaAllocator,
loaded: bool = false,

pub fn init(allocator: Allocator) !zram {
    var self = zram{
        .arena = try allocator.create(ArenaAllocator),
    };
    errdefer allocator.destroy(self.arena);
    self.arena.* = ArenaAllocator.init(allocator);
    errdefer self.arena.deinit();

    return self;
}

pub fn deinit(self: *zram) void {
    const allocator = self.arena.child_allocator;
    self.arena.deinit();
    allocator.destroy(self.arena);
}

pub fn get_modules(self: *zram, primary: []const u8) !void {
    const alloc = self.arena.allocator();

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

    const deps_p = try std.fmt.allocPrint(alloc, "/lib/modules/{s}/modules.dep", .{release});
    defer alloc.free(deps_p);
    const deps_f = try std.fs.openFileAbsolute(deps_p, .{});
    defer deps_f.close();

    var buf: [1024]u8 = undefined;
    var deps_r = deps_f.reader(&buf);

    while (deps_r.interface.takeDelimiterExclusive('\n')) |line| {
        if (mem.containsAtLeast(u8, line, 1, primary)) {
            if (mem.indexOfScalar(u8, line, ':')) |colon| {
                const mod_p = try std.fmt.allocPrint(alloc, "/lib/modules/{s}/{s}", .{ release, line[0..colon] });
                defer alloc.free(mod_p);
                const deps = line[colon + 1 ..];

                var it = mem.splitScalar(u8, deps, ' ');
                while (it.next()) |dep| {
                    if (dep.len > 0) {
                        const entry = try std.fmt.allocPrint(alloc, "/lib/modules/{s}/{s}", .{ release, dep });
                        defer alloc.free(entry);
                        log.debug("loading dep: {s}", .{entry});
                        try load_module(entry);
                    }
                }
                log.debug("loading {s}: {s}", .{ primary, mod_p });
                try load_module(mod_p);
                return;
            }
        }
    } else |err| switch (err) {
        error.EndOfStream, // stream ended not on a line break
        error.StreamTooLong, // line could not fit in buffer
        error.ReadFailed, // caller can check reader implementation for diagnostics
        => |e| return e,
    }
    return error.NoModule;
}

pub fn load_zram_module(self: *zram) !?i8 {
    const maybe_z = std.fs.openDirAbsolute("/sys/module/zram", .{}) catch null;
    if (maybe_z) |const_z| {
        var z = const_z;
        z.close();
        self.loaded = true;
        log.debug("zram already loaded", .{});
        return null;
    }

    try self.get_modules("zram");
    try self.get_modules("overlay");

    log.debug("loaded zram module successfully", .{});
    self.loaded = true;
    return 0;
}

pub fn load_module(module_p: []u8) !void {
    const module = try std.fs.openFileAbsolute(module_p, .{ .mode = .read_only });
    defer module.close();

    const MODULE_INIT_COMPRESSED_FILE: u32 = 4;

    const r2 = linux.E.init(linux.syscall3(
        .finit_module,
        @intCast(module.handle),
        @intFromPtr("".ptr),
        MODULE_INIT_COMPRESSED_FILE,
    ));
    if (r2 != .SUCCESS and r2 != .EXIST) {
        log.err("failed to init_module: {s}", .{@tagName(r2)});
        return error.InitModule;
    }
}

pub fn add_device(self: *zram) !i8 {
    const alloc = self.arena.allocator();
    while (!self.loaded) {
        const dev_n = try self.load_zram_module() orelse break;
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

    // Make sure that the device is really clean before configuring it.
    // Especially important on dirty reboots (eg. sudden power loss).
    try helpers.zblock_config_write(alloc, dev, "reset", "1");

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
