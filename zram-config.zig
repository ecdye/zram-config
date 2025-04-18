const std = @import("std");
const zstd = std.compress.zstd;
const linux = std.os.linux;
const SYS = linux.SYS;
const Allocator = std.mem.Allocator;
const log = std.log;

fn load_zram_mod(alloc: Allocator) !?i8 {
    const maybe_dir = std.fs.openDirAbsolute("/sys/module/zram", .{}) catch null;
    if (maybe_dir) |dir_const| {
        var dir = dir_const;
        dir.close();
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

    const res = linux.E.init(linux.syscall1(SYS.uname, @intFromPtr(&uts)));
    if (res != .SUCCESS) {
        log.err("failed to get uname: {s}", .{@tagName(res)});
        return error.uname;
    }

    const release = std.mem.sliceTo(&uts.release, 0);
    const zram_module_path = try std.fmt.allocPrint(
        alloc,
        "/lib/modules/{s}/kernel/drivers/block/zram/zram.ko.zst",
        .{release},
    );

    const file = try std.fs.openFileAbsolute(zram_module_path, .{});
    defer file.close();

    const raw_data_s = try file.getEndPos();
    const raw_data = try file.readToEndAlloc(alloc, raw_data_s);
    defer alloc.free(raw_data);

    const decomp_data = try zstd.decompress.decodeAlloc(alloc, raw_data, false, 8 * 1024 * 1024);
    defer alloc.free(decomp_data);

    const sys_result = linux.E.init(linux.syscall3(
        SYS.init_module,
        @intFromPtr(decomp_data.ptr),
        decomp_data.len,
        @intFromPtr("".ptr),
    ));
    if (sys_result != .SUCCESS) {
        log.err("init_module failed: {s}", .{@tagName(sys_result)});
        return error.init_module;
    }

    log.debug("zram loaded successfully!", .{});
    return 0;
}

fn init_zram_dev(
    alloc: Allocator,
    alg: []const u8,
    disk_s: []const u8,
    mem_l: []const u8,
    dev: ?i8,
) !i8 {
    const dev_n = dev orelse add_z_dev(alloc) catch |err| {
        log.err("failed to get new zram device: {!}", .{err});
        return err;
    };
    errdefer rem_z_dev(alloc, dev_n);

    set_config_val(alloc, dev_n, "comp_algorithm", alg) catch |err| {
        log.err("failed to set compression alg: {!}", .{err});
        return err;
    };

    set_config_val(alloc, dev_n, "disksize", disk_s) catch |err| {
        log.err("failed to set disk size: {!}", .{err});
        return err;
    };

    set_config_val(alloc, dev_n, "mem_limit", mem_l) catch |err| {
        log.err("failed to set mem limit: {!}", .{err});
        return err;
    };
    if (std.mem.eql(u8, mem_l, "0")) log.info("no memory limit set for /dev/zram{d}", .{dev_n});

    return dev_n;
}

fn add_z_dev(alloc: Allocator) !i8 {
    const file = try std.fs.openFileAbsolute("/sys/class/zram-control/hot_add", .{});
    defer file.close();

    const buf = try file.readToEndAlloc(alloc, 8);
    defer alloc.free(buf);

    const dev = std.mem.trimRight(u8, buf, "\n");
    return try std.fmt.parseInt(i8, dev, 10);
}

fn set_config_val(
    alloc: Allocator,
    dev_n: i8,
    setting: []const u8,
    val: []const u8,
) !void {
    const config_path = try std.fmt.allocPrint(alloc, "/sys/block/zram{d}/{s}", .{ dev_n, setting });
    const config_f = try std.fs.openFileAbsolute(config_path, .{ .mode = .write_only });
    defer config_f.close();
    _ = try config_f.write(val);
}

fn rem_z_dev(alloc: Allocator, dev_n: i8) void {
    set_config_val(alloc, dev_n, "reset", "1") catch |err| {
        log.err("failed to reset /dev/zram{d}: {!}", .{ dev_n, err });
    };

    const file = std.fs.openFileAbsolute(
        "/sys/class/zram-control/hot_remove",
        .{ .mode = .write_only },
    ) catch |err| {
        log.err("failed to get hot remove: {!}", .{err});
        return;
    };
    defer file.close();
    const dev_ns = std.fmt.allocPrint(alloc, "{d}", .{dev_n}) catch |err| {
        log.debug("failed to alloc string of dev_n: {d}, error: {!}", .{ dev_n, err });
        return;
    };
    _ = file.write(dev_ns) catch |err| {
        log.err("failed to write to hot remove: {!}", .{err});
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    const init_num = try load_zram_mod(alloc);

    const dev_num = init_zram_dev(alloc, "zstd", "2048", "1024", init_num) catch return;
    log.info("configured dev num: {d}", .{dev_num});
}
