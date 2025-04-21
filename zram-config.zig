const std = @import("std");
const zstd = std.compress.zstd;
const linux = std.os.linux;
const SYS = linux.SYS;
const Allocator = std.mem.Allocator;
const log = std.log;

const zDevList = @import("zDevList.zig");
const zDevEntry = @import("zDevEntry.zig");
const zConfig = @import("zConfig.zig");
const zConfigEntry = @import("zConfigEntry.zig");
const zSwapEntry = @import("zSwapEntry.zig");

fn load_zram_mod(alloc: Allocator) !?i8 {
    const maybe_dir = std.fs.openDirAbsolute("/sys/module/zram", .{}) catch null;
    if (maybe_dir) |dir_const| {
        var dir = dir_const;
        dir.close();
        log.debug("zram already loaded", .{});
        return null;
    }

    const Utsname = extern struct {
        sysname: [65]u8,
        nodename: [65]u8,
        release: [65]u8,
        version: [65]u8,
        machine: [65]u8,
        domainname: [65]u8,
    };

    var uts: Utsname = undefined;

    const res = linux.E.init(linux.syscall1(SYS.uname, @intFromPtr(&uts)));
    if (res != .SUCCESS) {
        log.err("failed to get uname: {s}", .{@tagName(res)});
        return error.uname;
    }

    const release = std.mem.sliceTo(&uts.release, 0);
    const zram_module_path = try std.fmt.allocPrint(
        alloc,
        "/lib/modules/{s}/kernel/drivers/block/zram/zram.ko.zst",
        .{release},
    );
    defer alloc.free(zram_module_path);

    const file = try std.fs.openFileAbsolute(zram_module_path, .{});
    defer file.close();

    const raw_data_s = try file.getEndPos();
    const raw_data = try file.readToEndAlloc(alloc, raw_data_s);
    defer alloc.free(raw_data);

    const decomp_data = try zstd.decompress.decodeAlloc(alloc, raw_data, false, 8 * 1024 * 1024);
    defer alloc.free(decomp_data);

    const sys_result = linux.E.init(linux.syscall3(
        SYS.init_module,
        @intFromPtr(decomp_data.ptr),
        decomp_data.len,
        @intFromPtr("".ptr),
    ));
    if (sys_result != .SUCCESS) {
        log.err("init_module failed: {s}", .{@tagName(sys_result)});
        return error.init_module;
    }

    log.debug("zram loaded successfully!", .{});
    return 0;
}

fn init_zram_dev(
    alloc: Allocator,
    alg: []const u8,
    disk_s: []const u8,
    mem_l: []const u8,
) !i8 {
    const dev_n = add_z_dev(alloc) catch |err| {
        log.err("failed to get new zram device: {!}", .{err});
        return err;
    };
    errdefer rem_z_dev(alloc, dev_n);

    set_config_val(alloc, dev_n, "comp_algorithm", alg) catch |err| {
        log.err("failed to set compression alg: {!}", .{err});
        return err;
    };

    set_config_val(alloc, dev_n, "disksize", disk_s) catch |err| {
        log.err("failed to set disk size: {!}", .{err});
        return err;
    };

    set_config_val(alloc, dev_n, "mem_limit", mem_l) catch |err| {
        log.err("failed to set mem limit: {!}", .{err});
        return err;
    };
    if (std.mem.eql(u8, mem_l, "0")) log.info("no memory limit set for /dev/zram{d}", .{dev_n});

    return dev_n;
}

fn add_z_dev(alloc: Allocator) !i8 {
    const maybe_dev = load_zram_mod(alloc) catch |err| {
        log.err("failed to load zram module: {!}", .{err});
        return err;
    };
    if (maybe_dev) |dev| return dev;

    const file = try std.fs.openFileAbsolute("/sys/class/zram-control/hot_add", .{});
    defer file.close();

    const buf = try file.readToEndAlloc(alloc, 8);
    defer alloc.free(buf);

    const dev = std.mem.trimRight(u8, buf, "\n");
    return try std.fmt.parseInt(i8, dev, 10);
}

fn set_config_val(
    alloc: Allocator,
    dev_n: i8,
    setting: []const u8,
    val: []const u8,
) !void {
    const config_path = try std.fmt.allocPrint(alloc, "/sys/block/zram{d}/{s}", .{ dev_n, setting });
    defer alloc.free(config_path);
    const config_f = try std.fs.openFileAbsolute(config_path, .{ .mode = .write_only });
    defer config_f.close();
    _ = try config_f.write(val);
}

fn rem_z_dev(alloc: Allocator, dev_n: i8) void {
    set_config_val(alloc, dev_n, "reset", "1") catch |err| {
        log.err("failed to reset /dev/zram{d}: {!}", .{ dev_n, err });
    };

    const file = std.fs.openFileAbsolute(
        "/sys/class/zram-control/hot_remove",
        .{ .mode = .write_only },
    ) catch |err| {
        log.err("failed to get hot remove: {!}", .{err});
        return;
    };
    defer file.close();
    const dev_ns = std.fmt.allocPrint(alloc, "{d}", .{dev_n}) catch |err| {
        log.debug("failed to alloc string of dev_n: {d}, error: {!}", .{ dev_n, err });
        return;
    };
    defer alloc.free(dev_ns);
    _ = file.write(dev_ns) catch |err| {
        log.err("failed to write to hot remove: {!}", .{err});
    };
}

fn create_swap(alloc: Allocator, entry: zSwapEntry) !i8 {
    const dev_n = init_zram_dev(alloc, entry.alg, entry.disk_s, entry.mem_l) catch |err| {
        log.err("failed to init zram device: {!}", .{err});
        return err;
    };
    const dev_p = try std.fmt.allocPrint(alloc, "/dev/zram{d}", .{dev_n});
    defer alloc.free(dev_p);

    const label = try std.fmt.allocPrint(alloc, "zram-config{d}", .{dev_n});
    defer alloc.free(label);
    const mkswap = [_][]const u8{ "mkswap", "--label", label, dev_p };
    var proc = std.process.Child.init(&mkswap, alloc);
    proc.stdin_behavior = .Ignore;
    proc.stderr_behavior = .Ignore;
    proc.stdout_behavior = .Ignore;
    try proc.spawn();
    _ = try proc.wait();

    const SWAP_FLAG_PREFER = 0x8000;
    const flags = SWAP_FLAG_PREFER | @as(usize, entry.swap_p);
    const res = linux.E.init(linux.syscall2(SYS.swapon, @intFromPtr(dev_p.ptr), flags));
    if (res != .SUCCESS) {
        log.err("failed to swapon: {!}", .{res});
    }

    const page_c = try std.fs.openFileAbsolute("/proc/sys/vm/page-cluster", .{ .mode = .write_only });
    defer page_c.close();
    const page_c_val = try std.fmt.allocPrint(alloc, "{d}", .{entry.page_c});
    defer alloc.free(page_c_val);
    try page_c.writeAll(page_c_val);

    const swap_n = try std.fs.openFileAbsolute("/proc/sys/vm/swappiness", .{ .mode = .write_only });
    defer swap_n.close();
    const swap_n_val = try std.fmt.allocPrint(alloc, "{d}", .{entry.swap_n});
    defer alloc.free(swap_n_val);
    try swap_n.writeAll(swap_n_val);

    return dev_n;
}

fn start_zram_config(alloc: Allocator) void {
    const config_j = std.fs.cwd().readFileAlloc(
        alloc,
        "zram-config.json",
        10 * 1024 * 1024,
    ) catch |err| {
        log.err("failed to open `zram-config.json`: {!}", .{err});
        return;
    };
    defer alloc.free(config_j);
    const config = std.json.parseFromSlice(zConfig, alloc, config_j, .{}) catch |err| {
        log.err("failed to parse config json: {!}", .{err});
        return;
    };
    defer config.deinit();

    if (config.value.version != 2) {
        log.warn("unsupported config file version, errors may occur", .{});
    }
    var list = std.ArrayList(zDevEntry).init(alloc);
    defer list.deinit();

    if (config.value.swaps) |swaps| {
        for (swaps) |swap| {
            const dev_n = create_swap(alloc, swap) catch |err| {
                log.err("failed to setup swap: {!}", .{err});
                break;
            };
            list.append(
                zDevEntry{
                    .z_dev = dev_n,
                    .swap = true,
                    .t_dir = null,
                    .b_dir = null,
                    .ol_dir = null,
                },
            ) catch |err| {
                log.err("failed to add item to list: {!}", .{err});
                return;
            };
            log.info("add zram device number: {d}", .{dev_n});
        }
    }
    if (config.value.dirs) |dirs| {
        for (dirs) |dir| {
            const dev_n = init_zram_dev(alloc, dir.alg, dir.disk_s, dir.mem_l) catch |err| {
                log.err("failed to init zram device: {!}", .{err});
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
                    .z_dev = dev_n,
                    .t_dir = dir.target_d,
                    .b_dir = bind,
                    .ol_dir = dir.oldlog_d,
                },
            ) catch |err| {
                log.err("failed to add item to list: {!}", .{err});
                return;
            };
            log.info("add zram device number: {d}", .{dev_n});
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

fn stop_zram_config(alloc: Allocator) void {
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
            remove_swap(alloc, entry.z_dev) catch |err| {
                log.err("failed to remove swap: {!}", .{err});
            };
        }
        rem_z_dev(alloc, entry.z_dev);
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
        .swap_n = 150,
        .page_c = 0,
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

    const config = zConfig{
        .version = 2,
        .swaps = swaps.items,
        .dirs = dirs.items,
    };
    const config_j = std.json.stringifyAlloc(alloc, config, .{ .whitespace = .indent_tab }) catch |err| {
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

pub fn main() void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

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
            start_zram_config(alloc);
            break;
        } else if (std.mem.eql(u8, arg, "stop")) {
            stop_zram_config(alloc);
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
