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

pub fn make_uuid_v4() [16]u8 {
    var uuid: [16]u8 = undefined;
    std.crypto.random.bytes(&uuid);

    // Set version (UUID v4): xxxx -> 0100xxxx
    uuid[6] = (uuid[6] & 0x0f) | 0x40;

    // Set variant (RFC4122 variant): xxxxxxxx -> 10xxxxxx
    uuid[8] = (uuid[8] & 0x3f) | 0x80;

    return uuid;
}
