const zConfigEntry = @import("zConfigEntry.zig");
const zSwapEntry = @import("zSwapEntry.zig");

pub const zConfig = @This();

version: u8,
dirs: ?[]const zConfigEntry,
swaps: ?[]const zSwapEntry,
