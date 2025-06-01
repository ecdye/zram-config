const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const zDevEntry = @import("zDevEntry.zig");

pub const zDevList = @This();

entries: ArrayList(zDevEntry),
alloc: Allocator,

pub fn init(alloc: Allocator) !zDevList {
    return zDevList{
        .entries = try ArrayList(zDevEntry).initCapacity(alloc, 0),
        .alloc = alloc,
    };
}

pub fn deinit(self: *zDevList) void {
    self.entries.deinit();
}

const JsonRepr = struct {
    entries: []zDevEntry,
};

pub fn append(self: *zDevList, entry: zDevEntry) !void {
    try self.entries.append(entry);
}

pub fn to_json(self: *zDevList, alloc: Allocator) ![]const u8 {
    const repr = JsonRepr{ .entries = self.entries.items };
    const json = std.json.stringifyAlloc(alloc, repr, .{ .whitespace = .indent_4 });
    return json;
}

pub fn from_json(alloc: Allocator, json: []const u8) !zDevList {
    const parsed = try std.json.parseFromSlice(JsonRepr, alloc, json, .{});
    defer parsed.deinit();

    var self = try zDevList.init(alloc);
    try self.entries.appendSlice(parsed.value.entries);
    return self;
}
