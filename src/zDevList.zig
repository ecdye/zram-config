const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const zDevEntry = @import("zDevEntry.zig");
const log = std.log;

pub const zDevList = @This();

entries: ArrayList(zDevEntry),
alloc: Allocator,

pub fn init(alloc: Allocator) !zDevList {
    return zDevList{
        .entries = .empty,
        .alloc = alloc,
    };
}

pub fn deinit(self: *zDevList) void {
    self.entries.deinit(self.alloc);
}

const JsonRepr = struct {
    entries: []zDevEntry,
};

pub fn append(self: *zDevList, entry: zDevEntry) !void {
    try self.entries.append(self.alloc, entry);
}

/// Converts zDevList into JSON representation. Caller owns memory.
pub fn to_json(self: *zDevList, alloc: Allocator) ![]const u8 {
    const repr = JsonRepr{ .entries = self.entries.items };
    return try std.json.Stringify.valueAlloc(alloc, repr, .{ .whitespace = .indent_tab });
}

/// Converts valid JSON into zDevList. You must call `deinit()` to clean up
/// allocated resources.
pub fn from_json(alloc: Allocator, json: []const u8) !zDevList {
    const parsed: std.json.Parsed(JsonRepr) = try std.json.parseFromSlice(
        JsonRepr,
        alloc,
        json,
        .{ .allocate = .alloc_always },
    );
    defer parsed.deinit();

    var self = try zDevList.init(alloc);
    try self.entries.appendSlice(alloc, parsed.value.entries);
    return self;
}
