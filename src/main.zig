const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log;

const zDevList = @import("zDevList.zig");
const zDevEntry = @import("zDevEntry.zig");
const zConfig = @import("zConfig.zig");
const zConfigEntry = @import("zConfigEntry.zig");
const zSwapEntry = @import("zSwapEntry.zig");
const zram_config_lib = @import("zram-config");
const zram = zram_config_lib.zram;
const config = zram_config_lib.config;

fn start_zram_config(alloc: Allocator, zz: *zram, zc: *config) void {
    const config_j = std.fs.cwd().readFileAlloc(
        alloc,
        "zram-config.json",
        10 * 1024 * 1024,
    ) catch |err| {
        log.err("failed to open `zram-config.json`: {!}", .{err});
        return;
    };
    defer alloc.free(config_j);
    const configS = std.json.parseFromSlice(zConfig, alloc, config_j, .{}) catch |err| {
        log.err("failed to parse config json: {!}", .{err});
        return;
    };
    defer configS.deinit();

    if (configS.value.version != 2) {
        log.warn("unsupported config file version, errors may occur", .{});
    }
    var list = std.ArrayList(zDevEntry).init(alloc);
    defer list.deinit();

    if (configS.value.swaps) |swaps| {
        for (swaps) |swap| {
            const dev = zz.*.add_device() catch |err| {
                log.err("failed to init zram device: {!}", .{err});
                return;
            };
            zz.*.config_device(dev, swap.alg, swap.disk_s, swap.mem_l) catch |err| {
                log.err("failed to configure zram device: {!}", .{err});
                return;
            };
            zc.*.zswap(dev, swap.swap_p, swap.page_c, swap.swap_n) catch |err| {
                log.err("failed to setup swap: {!}", .{err});
                break;
            };
            list.append(
                zDevEntry{
                    .z_dev = dev,
                    .swap = true,
                    .t_dir = null,
                    .b_dir = null,
                    .ol_dir = null,
                },
            ) catch |err| {
                log.err("failed to add item to list: {!}", .{err});
                return;
            };
            log.info("add zram device number: {d}", .{dev});
        }
    }
    if (configS.value.dirs) |dirs| {
        for (dirs) |dir| {
            const dev = zz.*.add_device() catch |err| {
                log.err("failed to init zram device: {!}", .{err});
                return;
            };
            zz.*.config_device(dev, dir.alg, dir.disk_s, dir.mem_l) catch |err| {
                log.err("failed to configure zram device: {!}", .{err});
                return;
            };
            const b_name = std.fs.path.basename(dir.target_d);
            const bind = std.fmt.allocPrint(alloc, "/opt/zram/{s}.bind", .{b_name}) catch |err| {
                log.err("failed to generate path for bind: {!}", .{err});
                return;
            };
            defer alloc.free(bind);
            list.append(
                zDevEntry{
                    .z_dev = dev,
                    .t_dir = dir.target_d,
                    .b_dir = bind,
                    .ol_dir = dir.oldlog_d,
                },
            ) catch |err| {
                log.err("failed to add item to list: {!}", .{err});
                return;
            };
            log.info("add zram device number: {d}", .{dev});
        }
    }

    const entry = zDevList{
        .entries = list.items,
    };
    const entry_j = std.json.stringifyAlloc(alloc, entry, .{}) catch |err| {
        log.err("failed to jsonify device list: {!}", .{err});
        return;
    };
    defer alloc.free(entry_j);

    const file = std.fs.cwd().createFile("z-dev-list.json", .{}) catch |err| {
        log.err("failed to create `z-dev-list.json`: {!}", .{err});
        return;
    };
    defer file.close();
    _ = file.write(entry_j) catch |err| {
        log.err("failed to write device list: {!}", .{err});
        return;
    };
}

fn stop_zram_config(alloc: Allocator, zz: *zram, zc: *config) void {
    const entry_j = std.fs.cwd().readFileAlloc(
        alloc,
        "z-dev-list.json",
        10 * 1024 * 1024,
    ) catch |err| {
        log.err("failed to open `z-dev-list.json`: {!}", .{err});
        return;
    };
    defer alloc.free(entry_j);
    const list = std.json.parseFromSlice(zDevList, alloc, entry_j, .{}) catch |err| {
        log.err("failed to parse device list: {!}", .{err});
        return;
    };
    defer list.deinit();

    for (list.value.entries) |entry| {
        if (entry.swap) {
            zc.*.rm_zswap(entry.z_dev) catch |err| {
                log.err("failed to swapoff zram device: {!}", .{err});
                return;
            };
        }
        zz.*.remove_device(entry.z_dev) catch |err| {
            log.err("failed to remove zram device: {!}", .{err});
            return;
        };
        log.info("removed zram device {d}", .{entry.z_dev});
    }

    std.fs.cwd().deleteFile("z-dev-list.json") catch |err| {
        log.err("failed to remove `z-dev-list.json`: {!}", .{err});
    };
}

fn create_config(alloc: Allocator) void {
    var swaps = std.ArrayList(zSwapEntry).init(alloc);
    defer swaps.deinit();
    swaps.append(zSwapEntry{
        .alg = "lzo-rle",
        .mem_l = "250M",
        .disk_s = "750M",
        .swap_p = 75,
        .swap_n = "150",
        .page_c = "0",
    }) catch |err| {
        log.err("failed to append to swaps: {!}", .{err});
    };

    var dirs = std.ArrayList(zConfigEntry).init(alloc);
    defer dirs.deinit();
    dirs.append(zConfigEntry{
        .alg = "lzo-rle",
        .mem_l = "50M",
        .disk_s = "150M",
        .target_d = "/home/pi",
        .oldlog_d = undefined,
    }) catch |err| {
        log.err("failed to append to dirs: {!}", .{err});
    };
    dirs.append(zConfigEntry{
        .alg = "lzo-rle",
        .mem_l = "50M",
        .disk_s = "150M",
        .target_d = "/var/log",
        .oldlog_d = "/opt/zram/oldlog",
    }) catch |err| {
        log.err("failed to append to dirs: {!}", .{err});
    };

    const configS = zConfig{
        .version = 2,
        .swaps = swaps.items,
        .dirs = dirs.items,
    };
    const config_j = std.json.stringifyAlloc(alloc, configS, .{ .whitespace = .indent_tab }) catch |err| {
        log.err("failed to jsonify config: {!}", .{err});
        return;
    };
    defer alloc.free(config_j);

    const file = std.fs.cwd().createFile("zram-config.json", .{}) catch |err| {
        log.err("failed to create `zram-config.json`: {!}", .{err});
        return;
    };

    defer file.close();
    _ = file.write(config_j) catch |err| {
        log.err("failed to write config: {!}", .{err});
        return;
    };
}

fn init_zram_config_lib(alloc: Allocator, zz: *zram, zc: *config) !void {
    zz.* = try zram.init(alloc);
    zc.* = try config.init(alloc);
}

fn deinit_zram_config_lib(zz: *zram, zc: *config) void {
    zz.*.deinit();
    zc.*.deinit();
}

pub fn main() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    var zz: zram = undefined;
    var zc: config = undefined;

    const help =
        \\usage: zram-config [-h | --help] <command> [<args>]
        \\
        \\commands:
        \\    start     start zram-config with configuration at `/etc/zram-config.json`
        \\    stop      stop the currently running zram-config instance
        \\    create    create a default `/etc/zram-config.json` config file
    ;
    const help_start =
        \\usage: zram-config start [-h | --help] [--config-path <path>]
        \\
        \\    -h, --help     display this help message and quit
        \\    --config-path <path>
        \\                   pass a custom configuration file path instead of `/etc/ztab`
    ;

    const args = std.process.argsAlloc(alloc) catch |err| {
        log.err("failed to parse arguments: {!}", .{err});
        return;
    };
    defer std.process.argsFree(alloc, args);

    if (args.len <= 1) {
        std.debug.print("{s}\n", .{help});
        return;
    }

    arg_p: for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "start")) {
            for (args[2..]) |arg2| {
                if (std.mem.eql(u8, arg2, "--help") or std.mem.eql(u8, arg2, "-h")) {
                    std.debug.print("{s}\n", .{help_start});
                    break :arg_p;
                } else if (std.mem.eql(u8, arg2, "--config-path")) {
                    std.debug.print("coming soon\n", .{});
                    break :arg_p;
                } else {
                    std.debug.print("invalid arguments\n{s}\n", .{help_start});
                    break :arg_p;
                }
            }
            init_zram_config_lib(alloc, &zz, &zc) catch |err| {
                log.err("failed to initialize zram config library: {!}", .{err});
                break;
            };
            defer deinit_zram_config_lib(&zz, &zc);
            start_zram_config(alloc, &zz, &zc);
            break;
        } else if (std.mem.eql(u8, arg, "stop")) {
            init_zram_config_lib(alloc, &zz, &zc) catch |err| {
                log.err("failed to initialize zram config library: {!}", .{err});
                break;
            };
            defer deinit_zram_config_lib(&zz, &zc);
            stop_zram_config(alloc, &zz, &zc);
            break;
        } else if (std.mem.eql(u8, arg, "config")) {
            create_config(alloc);
            break;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            std.debug.print("{s}\n", .{help});
            break;
        } else {
            std.debug.print("invalid arguments\n{s}\n", .{help});
            break;
        }
    }
}
