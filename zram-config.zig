const std = @import("std");
const zstd = std.compress.zstd;
const linux = std.os.linux;
const SYS = linux.SYS;

fn load_zram_mod(alloc: std.mem.Allocator) !void {
    const maybe_dir = try std.fs.openDirAbsolute("/sys/module/zram", .{}) catch null;
    if (maybe_dir) |dir_const| {
        var dir = dir_const;
        dir.close();
        std.debug.print("zram already loaded\n", .{});
        return;
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
        return;
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

    const raw_data = try file.readToEndAlloc(alloc, 10 * 1024 * 1024);
    defer alloc.free(raw_data);

    const decomp_data = try alloc.alloc(u8, 10 * 1024 * 1024);
    const decomp_size = try zstd.decompress.decode(decomp_data, raw_data, false);

    const sys_result = linux.E.init(linux.syscall3(
        SYS.init_module,
        @intFromPtr(decomp_data.ptr),
        decomp_size,
        @intFromPtr("".ptr),
    ));
    if (sys_result != .SUCCESS) {
        std.debug.print("init_module failed: {s}\n", .{@tagName(sys_result)});
        return;
    }

    std.debug.print("zram loaded successfully!\n", .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();

    _ = try load_zram_mod(alloc);
}
