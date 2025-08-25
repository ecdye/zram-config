const std = @import("std");
const Allocator = std.mem.Allocator;
const linux = std.os.linux;

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

pub fn mount_or_error(
    special: ?[*:0]const u8,
    dir: [*:0]const u8,
    fstype: ?[*:0]const u8,
    flags: u32,
    data: usize,
) !void {
    const res = linux.E.init(linux.mount(special, dir, fstype, flags, data));
    if (res != .SUCCESS) {
        switch (res) {
            .ACCES => return error.ACCES,
            .BUSY => return error.BUSY,
            .FAULT => return error.FAULT,
            .INVAL => return error.INVAL,
            .LOOP => return error.LOOP,
            .MFILE => return error.MFILE,
            .NAMETOOLONG => return error.NAMETOOLONG,
            .NODEV => return error.NODEV,
            .NOENT => return error.NOENT,
            .NOMEM => return error.NOMEM,
            .NOTBLK => return error.NOTBLK,
            .NOTDIR => return error.NOTDIR,
            .NXIO => return error.NXIO,
            .PERM => return error.PERM,
            .ROFS => return error.ROFS,
            else => unreachable,
        }
    }
}

pub fn umount_or_error(special: [*:0]const u8, flags: u32) !void {
    const res = linux.E.init(linux.umount2(special, flags));
    if (res != .SUCCESS) {
        switch (res) {
            .AGAIN => return error.AGAIN,
            .BUSY => return error.BUSY,
            .FAULT => return error.FAULT,
            .INVAL => return error.INVAL,
            .NAMETOOLONG => return error.NAMETOOLONG,
            .NOENT => return error.NOENT,
            .NOMEM => return error.NOMEM,
            .PERM => return error.PERM,
            else => unreachable,
        }
    }
}
