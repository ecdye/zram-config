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

fn load_active_config(alloc: Allocator) !zDevList {
    const dev_list_p = "/tmp/z-dev-list.json";
    const dev_list_f = try std.fs.openFileAbsolute(dev_list_p, .{});
    const dev_list_j = try dev_list_f.readToEndAlloc(alloc, 10 * 1024);
    defer alloc.free(dev_list_j);

    const dev_list = try zDevList.from_json(alloc, dev_list_j);
    return dev_list;
}

fn start_zram_config(alloc: Allocator, zz: *zram) void {
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
    var list: zDevList = load_active_config(alloc) catch blk: {
        const default = zDevList.init(alloc) catch |err| {
            log.err("failed to create zram device list in memory: {!}", .{err});
            return;
        };
        break :blk default;
    };
    defer list.deinit();

    if (configS.value.swaps) |swaps| {
        for (swaps) |swap| {
            const dev = zz.*.add_config_device(swap.alg, swap.disk_s, swap.mem_l) catch |err| {
                log.err("failed to configure zram swap device: {!}", .{err});
                return;
            };
            config.zswap(dev, swap.swap_p, swap.page_c, swap.swap_n) catch |err| {
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
            const dev = zz.*.add_config_device(dir.alg, dir.disk_s, dir.mem_l) catch |err| {
                log.err("failed to configure zram device: {!}", .{err});
                return;
            };
            const b_name = std.fs.path.basename(dir.target_d);
            const bind = std.fmt.allocPrint(alloc, "/opt/zram/{s}.bind", .{b_name}) catch |err| {
                log.err("failed to generate path for bind: {!}", .{err});
                return;
            };
            defer alloc.free(bind);
            config.zdir(dev, dir.target_d, bind) catch |err| {
                log.err("failed to configure dir: {!}", .{err});
            };

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

    const list_j = list.to_json(alloc) catch |err| {
        log.err("failed to jsonify zDevList: {!}", .{err});
        return;
    };
    defer alloc.free(list_j);

    const file = std.fs.cwd().createFile("z-dev-list.json", .{}) catch |err| {
        log.err("failed to create `z-dev-list.json`: {!}", .{err});
        return;
    };
    defer file.close();
    _ = file.write(list_j) catch |err| {
        log.err("failed to write device list: {!}", .{err});
        return;
    };
}

fn stop_zram_config(alloc: Allocator, zz: *zram) void {
    const list_j = std.fs.cwd().readFileAlloc(
        alloc,
        "z-dev-list.json",
        10 * 1024 * 1024,
    ) catch |err| {
        log.err("failed to open `z-dev-list.json`: {!}", .{err});
        return;
    };
    defer alloc.free(list_j);
    var list = zDevList.from_json(alloc, list_j) catch |err| {
        log.err("failed to parse device list: {!}", .{err});
        return;
    };
    defer list.deinit();

    for (list.entries.items) |entry| {
        if (entry.swap) {
            config.rm_zswap(entry.z_dev) catch |err| {
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
        .alg = "zstd",
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
        .alg = "zstd",
        .mem_l = "50M",
        .disk_s = "150M",
        .target_d = "/home/pi",
        .oldlog_d = undefined,
    }) catch |err| {
        log.err("failed to append to dirs: {!}", .{err});
    };
    dirs.append(zConfigEntry{
        .alg = "zstd",
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

fn init_zram_config_lib(alloc: Allocator, zz: *zram) !void {
    zz.* = try zram.init(alloc);
}

fn deinit_zram_config_lib(zz: *zram) void {
    zz.*.deinit();
}

pub fn main() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();
    var zz: zram = undefined;

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
            init_zram_config_lib(alloc, &zz) catch |err| {
                log.err("failed to initialize zram config library: {!}", .{err});
                break;
            };
            defer deinit_zram_config_lib(&zz);
            start_zram_config(alloc, &zz);
            break;
        } else if (std.mem.eql(u8, arg, "stop")) {
            init_zram_config_lib(alloc, &zz) catch |err| {
                log.err("failed to initialize zram config library: {!}", .{err});
                break;
            };
            defer deinit_zram_config_lib(&zz);
            stop_zram_config(alloc, &zz);
            break;
        } else if (std.mem.eql(u8, arg, "create")) {
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
