const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn zblock_config_write(
    alloc: Allocator,
    dev_n: i8,
    config: []const u8,
    val: []const u8,
) !void {
    const config_p = try std.fmt.allocPrint(alloc, "/sys/block/zram{d}/{s}", .{ dev_n, config });
    defer alloc.free(config_p);

    const config_f = try std.fs.openFileAbsolute(config_p, .{ .mode = .write_only });
    defer config_f.close();
    _ = try config_f.write(val);
}
