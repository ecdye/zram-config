const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log;

const zDevList = @import("zDevList.zig");
const zDevEntry = @import("zDevEntry.zig");
const zConfig = @import("zConfig.zig");
const zDirEntry = @import("zDirEntry.zig");
const zSwapEntry = @import("zSwapEntry.zig");
const zram_config_lib = @import("zram-config");
const zram = zram_config_lib.zram;
const config = zram_config_lib.config;
const zc_json = "/etc/zram-config.json";
const ac_json = "/tmp/z-dev-list.json";

fn load_ac_json(alloc: Allocator) !zDevList {
    const dev_list_f = try std.fs.openFileAbsoluteZ(ac_json, .{});
    const dev_list_j = try dev_list_f.readToEndAlloc(alloc, 10 * 1024 * 1024);
    defer alloc.free(dev_list_j);

    const ac = try zDevList.from_json(alloc, dev_list_j);
    return ac;
}

fn save_ac_json(alloc: Allocator, ac: *zDevList) !void {
    const ac_j = try ac.*.to_json(alloc);
    defer alloc.free(ac_j);

    const ac_f = try std.fs.createFileAbsoluteZ(ac_json, .{});
    defer ac_f.close();
    _ = try ac_f.write(ac_j);
}

fn load_zc_json(alloc: Allocator) !zConfig {
    const zc_f = try std.fs.openFileAbsoluteZ(zc_json, .{});
    const zc_j = try zc_f.readToEndAlloc(alloc, 10 * 1024 * 1024);
    defer alloc.free(zc_j);

    const zc = try zConfig.from_json(alloc, zc_j);
    return zc;
}

fn save_zc_json(alloc: Allocator, zc: *zConfig) !void {
    const zc_j = try zc.*.to_json(alloc);
    defer alloc.free(zc_j);

    const zc_f = try std.fs.createFileAbsoluteZ(zc_json, .{});
    defer zc_f.close();
    _ = try zc_f.write(zc_j);
}

fn start_zram_config(gpa: Allocator, zz: *zram) void {
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const alloc = arena.allocator();

    var zc = load_zc_json(alloc) catch |err| {
        log.err("failed to load `{s}`: {t}", .{ zc_json, err });
        return;
    };
    defer zc.deinit();
    for (zc.dirs.items) |dir| {
        log.debug("dir: {s}", .{dir.target_d});
    }

    if (zc.version != 2) {
        log.warn("unsupported config file version, errors may occur", .{});
    }
    var ac: zDevList = load_ac_json(alloc) catch blk: {
        const default = zDevList.init(alloc) catch |err| {
            log.err("failed to create zram device list in memory: {t}", .{err});
            return;
        };
        break :blk default;
    };
    defer ac.deinit();

    for (zc.swaps.items) |swap| {
        const dev = zz.*.add_config_device(swap.alg, swap.disk_s, swap.mem_l) catch |err| {
            log.err("failed to configure zram swap device: {t}", .{err});
            return;
        };
        config.zswap(dev, swap.swap_p, swap.page_c, swap.swap_n) catch |err| {
            log.err("failed to setup swap: {t}", .{err});
            break;
        };
        ac.append(
            zDevEntry{
                .z_dev = dev,
                .swap = true,
                .t_dir = null,
                .b_dir = null,
                .ol_dir = null,
            },
        ) catch |err| {
            log.err("failed to add item to list: {t}", .{err});
            return;
        };
        log.info("add zram device number: {d}, swap", .{dev});
    }
    for (zc.dirs.items) |dir| {
        const dev = zz.*.add_config_device(dir.alg, dir.disk_s, dir.mem_l) catch |err| {
            log.err("failed to configure zram device: {t}", .{err});
            return;
        };
        const b_name = std.fs.path.basename(dir.target_d);
        const bind = std.fmt.allocPrint(alloc, "{s}.bind", .{b_name}) catch |err| {
            log.err("failed to generate path for bind: {t}", .{err});
            return;
        };
        log.debug("bind: {s}", .{bind});
        var target_d_buf = alloc.alloc(u8, dir.target_d.len + 1) catch |err| {
            log.err("failed to allocate memory for null term: {t}", .{err});
            return;
        };
        std.mem.copyForwards(u8, target_d_buf[0..dir.target_d.len], dir.target_d);
        target_d_buf[target_d_buf.len - 1] = 0;

        config.zdir(
            alloc,
            dev,
            target_d_buf[0..dir.target_d.len :0],
            bind,
            dir.oldlog_d,
        ) catch |err| {
            log.err("failed to configure dir: {t}", .{err});
        };

        ac.append(
            zDevEntry{
                .z_dev = dev,
                .t_dir = dir.target_d,
                .b_dir = bind,
                .ol_dir = dir.oldlog_d,
            },
        ) catch |err| {
            log.err("failed to add item to list: {t}", .{err});
            return;
        };
        log.info("add zram device number: {d}, dir", .{dev});
    }

    save_ac_json(alloc, &ac) catch |err| {
        log.err("failed to save `{s}`: {t}", .{ ac_json, err });
        return;
    };
}

fn stop_zram_config(alloc: Allocator, zz: *zram) void {
    var ac = load_ac_json(alloc) catch |err| {
        log.err("failed to load `{s}`: {t}", .{ ac_json, err });
        return;
    };
    defer ac.deinit();

    for (ac.entries.items) |entry| {
        if (entry.swap) {
            config.rm_zswap(entry.z_dev) catch |err| {
                log.err("failed to swapoff zram device: {t}", .{err});
                return;
            };
        }
        if (entry.b_dir) |b_dir| {
            config.rm_zdir(alloc, entry.z_dev, b_dir, entry.t_dir.?) catch |err| {
                log.err("failed to remove zram device: {t}", .{err});
                return;
            };
        }
        zz.*.remove_device(entry.z_dev) catch |err| {
            log.err("failed to remove zram device: {t}", .{err});
            return;
        };
        log.info("removed zram device {d}", .{entry.z_dev});
    }

    std.fs.deleteFileAbsoluteZ(ac_json) catch |err| {
        log.err("failed to remove `{s}`: {t}", .{ ac_json, err });
        return;
    };
}

fn create_config(alloc: Allocator) void {
    var zc = zConfig.init(alloc) catch |err| {
        log.err("failed to init zConfig: {t}", .{err});
        return;
    };
    defer zc.deinit();

    zc.append_swap(zSwapEntry{
        .alg = "zstd",
        .mem_l = "250M",
        .disk_s = "750M",
        .swap_p = 75,
        .swap_n = "150",
        .page_c = "0",
    }) catch |err| {
        log.err("failed to append to swaps: {t}", .{err});
    };

    zc.append_dir(zDirEntry{
        .alg = "zstd",
        .mem_l = "50M",
        .disk_s = "150M",
        .target_d = "/home/pi",
        .oldlog_d = null,
    }) catch |err| {
        log.err("failed to append to dirs: {t}", .{err});
    };
    zc.append_dir(zDirEntry{
        .alg = "zstd",
        .mem_l = "50M",
        .disk_s = "150M",
        .target_d = "/var/log",
        .oldlog_d = "/opt/zram/oldlog",
    }) catch |err| {
        log.err("failed to append to dirs: {t}", .{err});
    };

    save_zc_json(alloc, &zc) catch |err| {
        log.err("failed to save `{s}`: {t}", .{ zc_json, err });
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
        \\                   pass a custom configuration file path instead of `/etc/zram-config.json`
    ;

    const args = std.process.argsAlloc(alloc) catch |err| {
        log.err("failed to parse arguments: {t}", .{err});
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
                log.err("failed to initialize zram config library: {t}", .{err});
                break;
            };
            defer deinit_zram_config_lib(&zz);
            start_zram_config(alloc, &zz);
            break;
        } else if (std.mem.eql(u8, arg, "stop")) {
            init_zram_config_lib(alloc, &zz) catch |err| {
                log.err("failed to initialize zram config library: {t}", .{err});
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
