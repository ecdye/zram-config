const std = @import("std");
const zstd = std.compress.zstd;
const linux = std.os.linux;
const SYS = linux.SYS;
const Allocator = std.mem.Allocator;

fn load_zram_mod(alloc: Allocator) !bool {
    const maybe_dir = std.fs.openDirAbsolute("/sys/module/zram", .{}) catch null;
    if (maybe_dir) |dir_const| {
        var dir = dir_const;
        dir.close();
        std.debug.print("zram already loaded\n", .{});
        return true;
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
        std.debug.print("failed to get uname: {s}\n", .{@tagName(res)});
        return false;
    }

    const release = std.mem.sliceTo(&uts.release, 0);
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const zram_module_path = try std.fmt.bufPrint(
        buf[0..],
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
        std.debug.print("init_module failed: {s}\n", .{@tagName(sys_result)});
        return false;
    }

    std.debug.print("zram loaded successfully!\n", .{});
    return true;
}

fn init_zram_dev(
    alloc: Allocator,
    alg: []const u8,
    disk_s: []const u8,
    mem_l: []const u8,
) i8 {
    const dev_num = add_z_dev(alloc) catch |err| {
        std.debug.print("failed to get new zram device: {!}\n", .{err});
        return -1;
    };
    const dev_config_path = std.fmt.allocPrint(alloc, "/sys/block/zram{d}", .{dev_num}) catch |err| {
        std.debug.print("failed to alloc dev config path: {!}\n", .{err});
        return -1;
    };

    set_config_val(alloc, dev_config_path, "comp_algorithm", alg) catch |err| {
        std.debug.print("failed to set compression alg: {!}\n", .{err});
        return -1;
    };

    set_config_val(alloc, dev_config_path, "disksize", disk_s) catch |err| {
        std.debug.print("failed to set disk size: {!}\n", .{err});
        return -1;
    };

    set_config_val(alloc, dev_config_path, "mem_limit", mem_l) catch |err| {
        std.debug.print("failed to set mem limit: {!}\n", .{err});
        return -1;
    };

    return dev_num;
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
    dev_config_path: []const u8,
    setting: []const u8,
    val: []const u8,
) !void {
    const config_path = try std.fmt.allocPrint(alloc, "{s}/{s}", .{ dev_config_path, setting });
    const config_f = try std.fs.openFileAbsolute(config_path, .{ .mode = .write_only });
    defer config_f.close();
    _ = try config_f.write(val);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    if (!try load_zram_mod(alloc)) return;

    const dev_num = init_zram_dev(alloc, "zstd", "2048", "1024");
    if (dev_num == -1) return;
    std.debug.print("configured dev num: {d}\n", .{dev_num});
}
