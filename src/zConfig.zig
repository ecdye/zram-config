const std = @import("std");
const ArrayList = std.ArrayList;
const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const zDirEntry = @import("zDirEntry.zig");
const zSwapEntry = @import("zSwapEntry.zig");
const log = std.log;

pub const zConfig = @This();

version: u8,
dirs: ArrayList(zDirEntry),
swaps: ArrayList(zSwapEntry),
arena: *ArenaAllocator,

pub fn init(allocator: Allocator) !zConfig {
    var self = zConfig{
        .arena = try allocator.create(ArenaAllocator),
        .dirs = .empty,
        .swaps = .empty,
        .version = 2,
    };
    errdefer allocator.destroy(self.arena);
    self.arena.* = ArenaAllocator.init(allocator);
    errdefer self.arena.deinit();

    return self;
}

pub fn deinit(self: *zConfig) void {
    const allocator = self.arena.child_allocator;
    self.arena.deinit();
    allocator.destroy(self.arena);
}

pub fn append_swap(self: *zConfig, swap: zSwapEntry) !void {
    const alloc = self.arena.allocator();
    try self.swaps.append(alloc, swap);
}

pub fn append_dir(self: *zConfig, dir: zDirEntry) !void {
    const alloc = self.arena.allocator();
    try self.dirs.append(alloc, dir);
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
pub fn from_json(allocator: Allocator, json: []const u8) !zConfig {
    var self = try zConfig.init(allocator);
    const alloc = self.arena.allocator();

    const parsed: JsonRepr = try std.json.parseFromSliceLeaky(
        JsonRepr,
        alloc,
        json,
        .{ .allocate = .alloc_always },
    );

    self.version = parsed.version;
    try self.dirs.appendSlice(alloc, parsed.dirs);
    try self.swaps.appendSlice(alloc, parsed.swaps);
    return self;
}
