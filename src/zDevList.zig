const std = @import("std");
const ArrayList = std.ArrayList;
const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;
const zDevEntry = @import("zDevEntry.zig");
const log = std.log;

pub const zDevList = @This();

entries: ArrayList(zDevEntry),
arena: *ArenaAllocator,

pub fn init(allocator: Allocator) !zDevList {
    var self = zDevList{
        .arena = try allocator.create(ArenaAllocator),
        .entries = .empty,
    };
    errdefer allocator.destroy(self.arena);
    self.arena.* = ArenaAllocator.init(allocator);
    errdefer self.arena.deinit();

    return self;
}

pub fn deinit(self: *zDevList) void {
    const allocator = self.arena.child_allocator;
    self.arena.deinit();
    allocator.destroy(self.arena);
}

const JsonRepr = struct {
    entries: []zDevEntry,
};

pub fn append(self: *zDevList, entry: zDevEntry) !void {
    const alloc = self.arena.allocator();
    try self.entries.append(alloc, entry);
}

/// Converts zDevList into JSON representation. Caller owns memory.
pub fn to_json(self: *zDevList, alloc: Allocator) ![]const u8 {
    const repr = JsonRepr{ .entries = self.entries.items };
    return try std.json.Stringify.valueAlloc(alloc, repr, .{ .whitespace = .indent_tab });
}

/// Converts valid JSON into zDevList. You must call `deinit()` to clean up
/// allocated resources.
pub fn from_json(allocator: Allocator, json: []const u8) !zDevList {
    var self = try zDevList.init(allocator);
    const alloc = self.arena.allocator();

    const parsed: JsonRepr = try std.json.parseFromSliceLeaky(
        JsonRepr,
        alloc,
        json,
        .{ .allocate = .alloc_always },
    );

    try self.entries.appendSlice(alloc, parsed.entries);
    return self;
}
