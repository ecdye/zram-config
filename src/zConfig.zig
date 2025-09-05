const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const zDirEntry = @import("zDirEntry.zig");
const zSwapEntry = @import("zSwapEntry.zig");
const log = std.log;

pub const zConfig = @This();

version: u8,
dirs: ArrayList(zDirEntry),
swaps: ArrayList(zSwapEntry),
alloc: Allocator,

pub fn init(alloc: Allocator) zConfig {
    return .{
        .version = 2,
        .dirs = .empty,
        .swaps = .empty,
        .alloc = alloc,
    };
}

pub fn deinit(self: *zConfig) void {
    self.dirs.deinit(self.alloc);
    self.swaps.deinit(self.alloc);
}

pub fn append_swap(self: *zConfig, swap: zSwapEntry) !void {
    try self.swaps.append(self.alloc, swap);
}

pub fn append_dir(self: *zConfig, dir: zDirEntry) !void {
    try self.dirs.append(self.alloc, dir);
}

const JsonRepr = struct {
    version: u8,
    dirs: []zDirEntry,
    swaps: []zSwapEntry,
};

/// Converts zConfig into JSON representation. Caller owns memory.
pub fn to_json(self: *zConfig, alloc: Allocator) ![]const u8 {
    const repr = JsonRepr{
        .version = self.version,
        .dirs = self.dirs.items,
        .swaps = self.swaps.items,
    };
    return try std.json.Stringify.valueAlloc(alloc, repr, .{ .whitespace = .indent_tab });
}

/// Converts valid JSON into zConfig. You must call `deinit()` to clean up
/// allocated resources.
pub fn from_json(alloc: Allocator, json: []const u8) !zConfig {
    const parsed: std.json.Parsed(JsonRepr) = try std.json.parseFromSlice(
        JsonRepr,
        alloc,
        json,
        .{ .allocate = .alloc_always },
    );
    defer parsed.deinit();

    var self = zConfig.init(alloc);
    self.version = parsed.value.version;
    try self.dirs.appendSlice(alloc, parsed.value.dirs);
    try self.swaps.appendSlice(alloc, parsed.value.swaps);
    return self;
}
