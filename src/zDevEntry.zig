pub const zDevEntry = @This();

z_dev: i8,
swap: bool = false,
t_dir: ?[]const u8,
b_dir: ?[]const u8,
ol_dir: ?[]const u8,
