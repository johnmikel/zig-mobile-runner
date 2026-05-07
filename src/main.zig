const std = @import("std");
const android = @import("android.zig");
const android_emulator = @import("android_emulator.zig");
const bundle = @import("bundle.zig");
const command = @import("command.zig");
const config = @import("config.zig");
const doctor = @import("doctor.zig");
const errors = @import("errors.zig");
const fake_device = @import("fake_device.zig");
const ios = @import("ios.zig");
const ios_shim = @import("ios_shim.zig");
const importer = @import("importer.zig");
const json_rpc = @import("json_rpc.zig");
const report = @import("report.zig");
const runner = @import("runner.zig");
const scaffold = @import("scaffold.zig");
const scenario = @import("scenario.zig");
const selector = @import("selector.zig");
const trace = @import("trace.zig");
const types = @import("types.zig");
const uiautomator = @import("uiautomator.zig");
const validation = @import("validation.zig");
const version = @import("version.zig");

const Platform = enum {
    android,
    ios,
};

const default_config_path = ".zmr/config.json";

const PublicSchema = struct {
    name: []const u8,
    path: []const u8,
    id: []const u8,
    description: []const u8,
};

const public_schemas = [_]PublicSchema{
    .{ .name = "json-rpc", .path = "schemas/json-rpc.schema.json", .id = "https://zmr.dev/schemas/json-rpc.schema.json", .description = "JSON-RPC requests and responses used by zmr serve" },
    .{ .name = "scenario", .path = "schemas/scenario.schema.json", .id = "https://zmr.dev/schemas/scenario.schema.json", .description = "Scenario files consumed by zmr run and zmr validate" },
    .{ .name = "snapshot", .path = "schemas/snapshot.schema.json", .id = "https://zmr.dev/schemas/snapshot.schema.json", .description = "ObservationSnapshot JSON emitted by live RPC and persisted trace snapshots" },
    .{ .name = "action-result", .path = "schemas/action-result.schema.json", .id = "https://zmr.dev/schemas/action-result.schema.json", .description = "Typed action result shape reserved for richer protocol responses" },
    .{ .name = "trace-event", .path = "schemas/trace-event.schema.json", .id = "https://zmr.dev/schemas/trace-event.schema.json", .description = "One JSONL event row from events.jsonl" },
    .{ .name = "trace-manifest", .path = "schemas/trace-manifest.schema.json", .id = "https://zmr.dev/schemas/trace-manifest.schema.json", .description = "trace.json summary for one traced run" },
    .{ .name = "zmr-config", .path = "schemas/zmr-config.schema.json", .id = "https://zmr.dev/schemas/zmr-config.schema.json", .description = "App-local .zmr/config.json defaults used by the CLI and npm wizard" },
    .{ .name = "doctor-output", .path = "schemas/doctor-output.schema.json", .id = "https://zmr.dev/schemas/doctor-output.schema.json", .description = "Machine-readable zmr doctor --json setup diagnostics" },
    .{ .name = "init-output", .path = "schemas/init-output.schema.json", .id = "https://zmr.dev/schemas/init-output.schema.json", .description = "Machine-readable zmr init --json bootstrap output" },
    .{ .name = "import-output", .path = "schemas/import-output.schema.json", .id = "https://zmr.dev/schemas/import-output.schema.json", .description = "Machine-readable zmr import --json migration output" },
    .{ .name = "devices-output", .path = "schemas/devices-output.schema.json", .id = "https://zmr.dev/schemas/devices-output.schema.json", .description = "Machine-readable zmr devices --json discovery output" },
    .{ .name = "validate-output", .path = "schemas/validate-output.schema.json", .id = "https://zmr.dev/schemas/validate-output.schema.json", .description = "Machine-readable zmr validate --json scenario preflight output" },
    .{ .name = "version-output", .path = "schemas/version-output.schema.json", .id = "https://zmr.dev/schemas/version-output.schema.json", .description = "Machine-readable zmr version --json compatibility output" },
    .{ .name = "explain-output", .path = "schemas/explain-output.schema.json", .id = "https://zmr.dev/schemas/explain-output.schema.json", .description = "Machine-readable zmr explain --json failure triage output" },
    .{ .name = "run-output", .path = "schemas/run-output.schema.json", .id = "https://zmr.dev/schemas/run-output.schema.json", .description = "Machine-readable zmr run --json terminal summary output" },
    .{ .name = "release-manifest", .path = "schemas/release-manifest.schema.json", .id = "https://zmr.dev/schemas/release-manifest.schema.json", .description = "Machine-readable RELEASE_MANIFEST.json emitted with release archives" },
    .{ .name = "schemas-output", .path = "schemas/schemas-output.schema.json", .id = "https://zmr.dev/schemas/schemas-output.schema.json", .description = "Machine-readable zmr schemas --json public schema index" },
};

const RawRunOptions = struct {
    scenario_path: ?[]const u8 = null,
    serial: ?[]const u8 = null,
    trace_dir: ?[]const u8 = null,
    app_id: ?[]const u8 = null,
    android_shim_path: ?[]const u8 = null,
    ios_shim_path: ?[]const u8 = null,
    screen_recording: ?bool = null,
    android_avd_name: ?[]const u8 = null,
    android_restore_snapshot: ?[]const u8 = null,
    android_create_avd_if_missing: ?bool = null,
    android_avd_system_image: ?[]const u8 = null,
    android_avd_device_profile: ?[]const u8 = null,
    android_reset_before_run: ?bool = null,
    android_wait_ready: ?bool = null,
    platform: Platform = .android,
};

const ResolvedRunOptions = struct {
    scenario_path: ?[]const u8,
    serial: ?[]const u8,
    trace_dir: ?[]const u8,
    app_id: []const u8,
    android_shim_path: ?[]const u8,
    ios_shim_path: ?[]const u8,
    android_avd_name: ?[]const u8,
    android_restore_snapshot: ?[]const u8,
    android_create_avd_if_missing: bool,
    android_avd_system_image: ?[]const u8,
    android_avd_device_profile: ?[]const u8,
    android_reset_before_run: bool,
    android_wait_ready: bool,
    platform: Platform,
};

const RawServeOptions = struct {
    serial: ?[]const u8 = null,
    app_id: ?[]const u8 = null,
    trace_dir: ?[]const u8 = null,
    android_shim_path: ?[]const u8 = null,
    ios_shim_path: ?[]const u8 = null,
    platform: Platform = .android,
};

const ResolvedServeOptions = struct {
    serial: ?[]const u8,
    app_id: []const u8,
    trace_dir: ?[]const u8,
    android_shim_path: ?[]const u8,
    ios_shim_path: ?[]const u8,
    platform: Platform,
};

pub fn main() void {
    mainInner() catch |err| {
        writeTopLevelError(err);
        std.process.exit(exitCodeForError(err));
    };
}

fn mainInner() !void {
    const GeneralAllocator = if (@hasDecl(std.heap, "GeneralPurposeAllocator"))
        std.heap.GeneralPurposeAllocator
    else
        std.heap.DebugAllocator;
    var gpa = GeneralAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next();
    const command_name = args.next() orelse {
        try usage();
        return;
    };

    if (std.mem.eql(u8, command_name, "devices")) {
        try cmdDevices(allocator, &args);
    } else if (std.mem.eql(u8, command_name, "schemas")) {
        try cmdSchemas(&args);
    } else if (std.mem.eql(u8, command_name, "doctor")) {
        try cmdDoctor(allocator, &args);
    } else if (std.mem.eql(u8, command_name, "validate")) {
        try cmdValidate(allocator, &args);
    } else if (std.mem.eql(u8, command_name, "init")) {
        try cmdInit(allocator, &args);
    } else if (std.mem.eql(u8, command_name, "import")) {
        try cmdImport(allocator, &args);
    } else if (std.mem.eql(u8, command_name, "run")) {
        try cmdRun(allocator, &args);
    } else if (std.mem.eql(u8, command_name, "report")) {
        try cmdReport(allocator, &args);
    } else if (std.mem.eql(u8, command_name, "explain")) {
        try cmdExplain(allocator, &args);
    } else if (std.mem.eql(u8, command_name, "export")) {
        try cmdExport(allocator, &args);
    } else if (std.mem.eql(u8, command_name, "serve")) {
        try cmdServe(allocator, &args);
    } else if (std.mem.eql(u8, command_name, "version") or std.mem.eql(u8, command_name, "--version")) {
        try cmdVersion(&args);
    } else if (std.mem.eql(u8, command_name, "help") or std.mem.eql(u8, command_name, "--help")) {
        try usage();
    } else {
        std.debug.print("unknown command: {s}\n\n", .{command_name});
        try usage();
        return error.UnknownCommand;
    }
}

fn writeTopLevelError(err: anyerror) void {
    const public = errors.classify(err);
    const stderr = std.fs.File.stderr().deprecatedWriter();
    stderr.print("error[{s}]: {s}\n", .{ public.code, public.message }) catch {};
    if (err == error.CommandFailed) {
        stderr.writeAll("hint: run `zmr doctor --json` for setup diagnostics.\n") catch {};
    }
}

fn exitCodeForError(err: anyerror) u8 {
    return switch (err) {
        error.UnknownCommand,
        error.UnknownFlag,
        error.MissingScenarioPath,
        error.MissingDeviceSerial,
        error.MissingTraceDir,
        error.MissingAppId,
        error.MissingAdbPath,
        error.MissingXcrunPath,
        error.MissingZigPath,
        error.MissingPlatform,
        error.MissingParam,
        error.UnsupportedPlatform,
        error.UnsupportedTransport,
        => 2,
        else => 1,
    };
}

fn cmdVersion(args: *std.process.ArgIterator) !void {
    var json = false;
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--json")) {
            json = true;
        } else {
            return error.UnknownFlag;
        }
    }

    const stdout = std.fs.File.stdout().deprecatedWriter();
    if (json) return try version.writeJson(stdout);
    try version.writePlain(stdout);
}

fn cmdSchemas(args: *std.process.ArgIterator) !void {
    var json = false;
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--json")) {
            json = true;
        } else {
            return error.UnknownFlag;
        }
    }

    const stdout = std.fs.File.stdout().deprecatedWriter();
    if (json) return try writeSchemasJson(stdout);
    for (public_schemas) |schema_info| {
        try stdout.print("{s}\t{s}\n", .{ schema_info.name, schema_info.path });
    }
}

fn writeSchemasJson(writer: anytype) !void {
    try writer.print("{{\"ok\":true,\"count\":{d},\"schemas\":[", .{public_schemas.len});
    for (public_schemas, 0..) |schema_info, index| {
        if (index > 0) try writer.writeAll(",");
        try writer.writeAll("{\"name\":");
        try trace.writeJsonString(writer, schema_info.name);
        try writer.writeAll(",\"path\":");
        try trace.writeJsonString(writer, schema_info.path);
        try writer.writeAll(",\"id\":");
        try trace.writeJsonString(writer, schema_info.id);
        try writer.writeAll(",\"description\":");
        try trace.writeJsonString(writer, schema_info.description);
        try writer.writeAll("}");
    }
    try writer.writeAll("]}\n");
}

fn cmdDevices(allocator: std.mem.Allocator, args: *std.process.ArgIterator) !void {
    var platform: Platform = .android;
    var adb_path: []const u8 = "adb";
    var xcrun_path: []const u8 = "xcrun";
    var json = false;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--platform")) {
            platform = try parsePlatform(args.next() orelse return error.MissingPlatform);
        } else if (std.mem.eql(u8, arg, "--adb")) {
            adb_path = args.next() orelse return error.MissingAdbPath;
        } else if (std.mem.eql(u8, arg, "--xcrun")) {
            xcrun_path = args.next() orelse return error.MissingXcrunPath;
        } else if (std.mem.eql(u8, arg, "--json")) {
            json = true;
        } else {
            return error.UnknownFlag;
        }
    }

    const devices = switch (platform) {
        .android => try android.listDevices(allocator, adb_path),
        .ios => try ios.listDevices(allocator, xcrun_path),
    };
    defer {
        for (devices) |device| device.deinit(allocator);
        allocator.free(devices);
    }
    const stdout = std.fs.File.stdout().deprecatedWriter();
    if (json) return try writeDevicesJson(stdout, platform, devices);
    if (devices.len == 0) return try stdout.print("No {s} devices found.\n", .{@tagName(platform)});
    for (devices) |device| {
        try stdout.print("{s}\t{s}\n", .{ device.serial, device.state });
    }
}

fn writeDevicesJson(writer: anytype, platform: Platform, devices: []const types.DeviceInfo) !void {
    try writer.writeAll("{\"platform\":");
    try trace.writeJsonString(writer, @tagName(platform));
    try writer.print(",\"count\":{d},\"devices\":[", .{devices.len});
    for (devices, 0..) |device, index| {
        if (index > 0) try writer.writeAll(",");
        try writer.writeAll("{\"serial\":");
        try trace.writeJsonString(writer, device.serial);
        try writer.writeAll(",\"state\":");
        try trace.writeJsonString(writer, device.state);
        try writer.writeAll("}");
    }
    try writer.writeAll("]}\n");
}

fn cmdDoctor(allocator: std.mem.Allocator, args: *std.process.ArgIterator) !void {
    var options = doctor.Options{};
    var json = false;
    var strict = false;
    var config_path: ?[]const u8 = null;
    var explicit_config = false;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--adb")) {
            options.adb_path = args.next() orelse return error.MissingAdbPath;
        } else if (std.mem.eql(u8, arg, "--android-shim")) {
            options.android_shim_path = args.next() orelse return error.MissingAndroidShimPath;
        } else if (std.mem.eql(u8, arg, "--xcrun")) {
            options.xcrun_path = args.next() orelse return error.MissingXcrunPath;
        } else if (std.mem.eql(u8, arg, "--ios-shim")) {
            options.ios_shim_path = args.next() orelse return error.MissingIosShimPath;
        } else if (std.mem.eql(u8, arg, "--zig")) {
            options.zig_path = args.next() orelse return error.MissingZigPath;
        } else if (std.mem.eql(u8, arg, "--json")) {
            json = true;
        } else if (std.mem.eql(u8, arg, "--strict")) {
            strict = true;
        } else if (std.mem.eql(u8, arg, "--config")) {
            config_path = args.next() orelse return error.MissingConfigPath;
            explicit_config = true;
        } else {
            return error.UnknownFlag;
        }
    }

    const actual_config_path = config_path orelse default_config_path;
    var config_check: ?doctor.Check = null;
    defer if (config_check) |check| check.deinit(allocator);

    var loaded_config = loadConfigIfPresent(allocator, config_path) catch |err| blk: {
        const field_path = try config.errorFieldPathForFile(allocator, actual_config_path, err);
        defer if (field_path) |value| allocator.free(value);
        config_check = try doctor.checkConfigError(allocator, actual_config_path, err, field_path);
        break :blk null;
    };
    defer if (loaded_config) |*cfg| cfg.deinit(allocator);
    if (loaded_config) |cfg| {
        if (explicit_config) config_check = try doctor.checkConfigLoaded(allocator, actual_config_path);
        if (std.mem.eql(u8, options.adb_path, "adb")) options.adb_path = cfg.tools.adb_path orelse options.adb_path;
        options.android_shim_path = options.android_shim_path orelse cfg.tools.android_shim_path;
        options.android_smoke_scenario = cfg.android.smoke_scenario;
        if (std.mem.eql(u8, options.xcrun_path, "xcrun")) options.xcrun_path = cfg.tools.xcrun_path orelse options.xcrun_path;
        options.ios_shim_path = options.ios_shim_path orelse cfg.tools.ios_shim_path;
        options.ios_smoke_scenario = cfg.ios.smoke_scenario;
        if (std.mem.eql(u8, options.zig_path, "zig")) options.zig_path = cfg.tools.zig_path orelse options.zig_path;
    }

    const checks = try doctor.run(allocator, options);
    defer {
        for (checks) |check| check.deinit(allocator);
        allocator.free(checks);
    }

    const stdout = std.fs.File.stdout().deprecatedWriter();
    if (json) {
        try writeDoctorJson(stdout, config_check, checks);
    } else {
        try writeDoctorText(stdout, config_check, checks);
    }
    if (strict and !doctorChecksHealthy(config_check, checks)) std.process.exit(1);
}

fn cmdValidate(allocator: std.mem.Allocator, args: *std.process.ArgIterator) !void {
    const path = args.next() orelse return error.MissingScenarioPath;
    var json = false;
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--json")) {
            json = true;
        } else {
            return error.UnknownFlag;
        }
    }

    const result = try validation.validateFile(allocator, path);
    defer result.deinit(allocator);

    const stdout = std.fs.File.stdout().deprecatedWriter();
    if (json) {
        try writeValidationJson(stdout, path, result);
    } else {
        try writeValidationText(stdout, path, result);
    }
    if (!result.ok) std.process.exit(1);
}

fn cmdInit(allocator: std.mem.Allocator, args: *std.process.ArgIterator) !void {
    var path: []const u8 = "zmr-scenario.json";
    var dir: []const u8 = ".";
    var app_id: []const u8 = "com.example.mobiletest";
    var app_scaffold = false;
    var force = false;
    var json = false;
    var path_set = false;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--app-id")) {
            app_id = args.next() orelse return error.MissingAppId;
        } else if (std.mem.eql(u8, arg, "--app")) {
            app_scaffold = true;
        } else if (std.mem.eql(u8, arg, "--dir")) {
            dir = args.next() orelse return error.MissingDirectory;
        } else if (std.mem.eql(u8, arg, "--force")) {
            force = true;
        } else if (std.mem.eql(u8, arg, "--json")) {
            json = true;
        } else if (std.mem.startsWith(u8, arg, "--")) {
            return error.UnknownFlag;
        } else if (app_scaffold) {
            return error.UnknownFlag;
        } else if (!path_set) {
            path = arg;
            path_set = true;
        } else {
            return error.UnknownFlag;
        }
    }

    const stdout = std.fs.File.stdout().deprecatedWriter();
    if (app_scaffold) {
        try scaffold.writeAppScaffold(allocator, dir, app_id, force);
        if (json) return try writeInitAppJson(stdout, dir, app_id);
        try stdout.print("created {s}/.zmr/config.json\n", .{dir});
        try stdout.print("created {s}/.zmr/android-smoke.json\n", .{dir});
        try stdout.print("created {s}/.zmr/ios-smoke.json\n", .{dir});
        try stdout.print("next: zmr doctor --strict --json --config {s}/.zmr/config.json\n", .{dir});
        return;
    }

    try scaffold.writeStarterScenario(allocator, path, app_id, force);
    if (json) return try writeInitScenarioJson(stdout, path, app_id);
    try stdout.print("created {s}\n", .{path});
}

fn cmdImport(allocator: std.mem.Allocator, args: *std.process.ArgIterator) !void {
    const format = args.next() orelse return error.MissingImportFormat;
    const source_path = args.next() orelse return error.MissingImportPath;
    var out_path: ?[]const u8 = null;
    var name: ?[]const u8 = null;
    var app_id: ?[]const u8 = null;
    var force = false;
    var json = false;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--out")) {
            out_path = args.next() orelse return error.MissingImportOut;
        } else if (std.mem.eql(u8, arg, "--name")) {
            name = args.next() orelse return error.MissingImportName;
        } else if (std.mem.eql(u8, arg, "--app-id")) {
            app_id = args.next() orelse return error.MissingAppId;
        } else if (std.mem.eql(u8, arg, "--force")) {
            force = true;
        } else if (std.mem.eql(u8, arg, "--json")) {
            json = true;
        } else {
            return error.UnknownFlag;
        }
    }

    if (!std.mem.eql(u8, format, "flow-yaml")) return error.UnsupportedImportFormat;
    const actual_out = out_path orelse return error.MissingImportOut;
    const result = try importer.importFlowYamlFile(allocator, source_path, actual_out, .{
        .name = name,
        .app_id = app_id,
        .force = force,
    });
    defer result.deinit(allocator);

    const stdout = std.fs.File.stdout().deprecatedWriter();
    if (json) return try writeImportJson(stdout, format, source_path, result);
    try stdout.print("wrote {s}\n", .{result.out_path});
}

fn writeImportJson(writer: anytype, format: []const u8, source_path: []const u8, result: importer.ImportResult) !void {
    try writer.writeAll("{\"ok\":true,\"format\":");
    try trace.writeJsonString(writer, format);
    try writer.writeAll(",\"source\":");
    try trace.writeJsonString(writer, source_path);
    try writer.writeAll(",\"out\":");
    try trace.writeJsonString(writer, result.out_path);
    try writer.writeAll(",\"name\":");
    try trace.writeJsonString(writer, result.name);
    try writer.writeAll(",\"appId\":");
    if (result.app_id) |app_id| {
        try trace.writeJsonString(writer, app_id);
    } else {
        try writer.writeAll("null");
    }
    try writer.print(",\"stepCount\":{d}", .{result.step_count});
    try writer.writeAll(",\"next\":\"zmr validate ");
    try writeJsonStringContent(writer, result.out_path);
    try writer.writeAll("\"}\n");
}

fn writeInitAppJson(writer: anytype, dir: []const u8, app_id: []const u8) !void {
    try writer.writeAll("{\"ok\":true,\"mode\":\"app\",\"dir\":");
    try trace.writeJsonString(writer, dir);
    try writer.writeAll(",\"appId\":");
    try trace.writeJsonString(writer, app_id);
    try writer.writeAll(",\"created\":[");
    try writeJoinedPathJson(writer, dir, ".zmr/config.json");
    try writer.writeAll(",");
    try writeJoinedPathJson(writer, dir, ".zmr/android-smoke.json");
    try writer.writeAll(",");
    try writeJoinedPathJson(writer, dir, ".zmr/ios-smoke.json");
    try writer.writeAll("],\"next\":");
    try writer.writeAll("\"zmr doctor --strict --json --config ");
    try writeJoinedPathJsonContent(writer, dir, ".zmr/config.json");
    try writer.writeAll("\"}\n");
}

fn writeInitScenarioJson(writer: anytype, path: []const u8, app_id: []const u8) !void {
    try writer.writeAll("{\"ok\":true,\"mode\":\"scenario\",\"appId\":");
    try trace.writeJsonString(writer, app_id);
    try writer.writeAll(",\"created\":[");
    try trace.writeJsonString(writer, path);
    try writer.writeAll("],\"next\":\"zmr validate ");
    try writeJsonStringContent(writer, path);
    try writer.writeAll("\"}\n");
}

fn writeJoinedPathJson(writer: anytype, root: []const u8, child: []const u8) !void {
    try writer.writeAll("\"");
    try writeJoinedPathJsonContent(writer, root, child);
    try writer.writeAll("\"");
}

fn writeJoinedPathJsonContent(writer: anytype, root: []const u8, child: []const u8) !void {
    try writeJsonStringContent(writer, root);
    if (root.len > 0 and !std.mem.endsWith(u8, root, "/")) try writer.writeAll("/");
    try writeJsonStringContent(writer, child);
}

fn writeJsonStringContent(writer: anytype, value: []const u8) !void {
    for (value) |ch| {
        switch (ch) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            0...7, 11, 12, 14...31 => try writer.print("\\u{x:0>4}", .{ch}),
            else => try writer.writeAll(&.{ch}),
        }
    }
}

fn cmdRun(allocator: std.mem.Allocator, args: *std.process.ArgIterator) !void {
    var raw = RawRunOptions{};
    var adb_path: []const u8 = "adb";
    var emulator_path: []const u8 = "emulator";
    var avdmanager_path: []const u8 = "avdmanager";
    var xcrun_path: []const u8 = "xcrun";
    var adb_path_set = false;
    var emulator_path_set = false;
    var avdmanager_path_set = false;
    var xcrun_path_set = false;
    var config_path: ?[]const u8 = null;
    var json = false;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--device")) {
            raw.serial = args.next() orelse return error.MissingDeviceSerial;
        } else if (std.mem.eql(u8, arg, "--trace-dir")) {
            raw.trace_dir = args.next() orelse return error.MissingTraceDir;
        } else if (std.mem.eql(u8, arg, "--app-id")) {
            raw.app_id = args.next() orelse return error.MissingAppId;
        } else if (std.mem.eql(u8, arg, "--adb")) {
            adb_path = args.next() orelse return error.MissingAdbPath;
            adb_path_set = true;
        } else if (std.mem.eql(u8, arg, "--emulator")) {
            emulator_path = args.next() orelse return error.MissingEmulatorPath;
            emulator_path_set = true;
        } else if (std.mem.eql(u8, arg, "--avdmanager")) {
            avdmanager_path = args.next() orelse return error.MissingAvdmanagerPath;
            avdmanager_path_set = true;
        } else if (std.mem.eql(u8, arg, "--android-shim")) {
            raw.android_shim_path = args.next() orelse return error.MissingAndroidShimPath;
        } else if (std.mem.eql(u8, arg, "--xcrun")) {
            xcrun_path = args.next() orelse return error.MissingXcrunPath;
            xcrun_path_set = true;
        } else if (std.mem.eql(u8, arg, "--ios-shim")) {
            raw.ios_shim_path = args.next() orelse return error.MissingIosShimPath;
        } else if (std.mem.eql(u8, arg, "--platform")) {
            raw.platform = try parsePlatform(args.next() orelse return error.MissingPlatform);
        } else if (std.mem.eql(u8, arg, "--config")) {
            config_path = args.next() orelse return error.MissingConfigPath;
        } else if (std.mem.eql(u8, arg, "--screen-record")) {
            raw.screen_recording = true;
        } else if (std.mem.eql(u8, arg, "--no-screen-record")) {
            raw.screen_recording = false;
        } else if (std.mem.eql(u8, arg, "--android-avd")) {
            raw.android_avd_name = args.next() orelse return error.MissingAndroidAvdName;
        } else if (std.mem.eql(u8, arg, "--restore-snapshot")) {
            raw.android_restore_snapshot = args.next() orelse return error.MissingAndroidSnapshotName;
        } else if (std.mem.eql(u8, arg, "--create-avd-if-missing")) {
            raw.android_create_avd_if_missing = true;
        } else if (std.mem.eql(u8, arg, "--avd-system-image")) {
            raw.android_avd_system_image = args.next() orelse return error.MissingAndroidAvdSystemImage;
        } else if (std.mem.eql(u8, arg, "--avd-device")) {
            raw.android_avd_device_profile = args.next() orelse return error.MissingAndroidAvdDeviceProfile;
        } else if (std.mem.eql(u8, arg, "--reset-emulator")) {
            raw.android_reset_before_run = true;
        } else if (std.mem.eql(u8, arg, "--wait-emulator")) {
            raw.android_wait_ready = true;
        } else if (std.mem.eql(u8, arg, "--json")) {
            json = true;
        } else if (std.mem.startsWith(u8, arg, "--")) {
            return error.UnknownFlag;
        } else if (raw.scenario_path == null) {
            raw.scenario_path = arg;
        } else {
            return error.UnknownFlag;
        }
    }

    var loaded_config = try loadConfigIfPresent(allocator, config_path);
    defer if (loaded_config) |*cfg| cfg.deinit(allocator);
    if (loaded_config) |cfg| {
        if (!adb_path_set) {
            if (cfg.tools.adb_path) |path| adb_path = path;
        }
        if (!emulator_path_set) {
            if (cfg.tools.emulator_path) |path| emulator_path = path;
        }
        if (!avdmanager_path_set) {
            if (cfg.tools.avdmanager_path) |path| avdmanager_path = path;
        }
        if (!xcrun_path_set) {
            if (cfg.tools.xcrun_path) |path| xcrun_path = path;
        }
    }
    const resolved = if (loaded_config) |cfg| resolveRunOptions(raw, cfg) else resolveRunOptions(raw, null);
    var capture = if (loaded_config) |cfg| traceCaptureOptions(cfg) else trace.CaptureOptions{};
    if (raw.screen_recording) |enabled| capture.capture_screen_recording = enabled;
    const scenario_path = resolved.scenario_path orelse return error.MissingScenarioPath;

    const script = try scenario.parseFile(allocator, scenario_path);
    defer script.deinit(allocator);
    const app_id = if (raw.app_id) |_| resolved.app_id else script.app_id orelse resolved.app_id;

    const run_error: ?anyerror = blk: {
        switch (resolved.platform) {
            .android => {
                if (androidPreflightOptions(resolved, adb_path, emulator_path, avdmanager_path)) |preflight| {
                    try android_emulator.runPreflight(allocator, preflight);
                }
                var device = try android.AndroidDevice.initWithShim(allocator, adb_path, resolved.serial, app_id, resolved.android_shim_path);
                defer device.deinit();
                runAndroidWithTrace(allocator, &device, script, resolved.trace_dir, capture) catch |err| break :blk err;
            },
            .ios => {
                var device = try ios.IosDevice.initWithShim(allocator, xcrun_path, resolved.serial, app_id, resolved.ios_shim_path);
                defer device.deinit();
                runWithTrace(allocator, &device, script, resolved.trace_dir, capture) catch |err| break :blk err;
            },
        }
        break :blk null;
    };

    if (json) try writeRunSummaryJson(
        allocator,
        std.fs.File.stdout().deprecatedWriter(),
        resolved.trace_dir,
        script.name,
        app_id,
        run_error,
    );
    if (run_error) |err| return err;
}

fn writeRunSummaryJson(
    allocator: std.mem.Allocator,
    writer: anytype,
    trace_dir: ?[]const u8,
    fallback_scenario: []const u8,
    fallback_app_id: []const u8,
    run_error: ?anyerror,
) !void {
    if (trace_dir) |dir| {
        const manifest_path = try std.fs.path.join(allocator, &.{ dir, "trace.json" });
        defer allocator.free(manifest_path);
        if (std.fs.cwd().readFileAlloc(allocator, manifest_path, 1024 * 1024)) |content| {
            defer allocator.free(content);
            const parsed = std.json.parseFromSlice(std.json.Value, allocator, content, .{}) catch null;
            if (parsed) |manifest| {
                defer manifest.deinit();
                if (manifest.value == .object) {
                    return try writeRunSummaryFromManifest(writer, dir, manifest.value.object, run_error);
                }
            }
        } else |_| {}
    }

    const ok = run_error == null;
    try writer.writeAll("{\"ok\":");
    try writer.writeAll(if (ok) "true" else "false");
    try writer.writeAll(",\"status\":");
    try trace.writeJsonString(writer, if (ok) "passed" else "failed");
    try writer.writeAll(",\"scenario\":");
    try trace.writeJsonString(writer, fallback_scenario);
    try writer.writeAll(",\"appId\":");
    try trace.writeJsonString(writer, fallback_app_id);
    if (run_error) |err| {
        try writer.writeAll(",\"error\":");
        try trace.writeJsonString(writer, @errorName(err));
    }
    try writer.writeAll("}\n");
}

fn writeRunSummaryFromManifest(
    writer: anytype,
    trace_dir: []const u8,
    manifest: std.json.ObjectMap,
    run_error: ?anyerror,
) !void {
    const status = jsonStringField(manifest, "status") orelse if (run_error == null) "passed" else "failed";
    try writer.writeAll("{\"ok\":");
    try writer.writeAll(if (std.mem.eql(u8, status, "passed")) "true" else "false");
    try writer.writeAll(",\"status\":");
    try trace.writeJsonString(writer, status);
    if (jsonStringField(manifest, "scenarioName")) |value| {
        try writer.writeAll(",\"scenario\":");
        try trace.writeJsonString(writer, value);
    }
    if (jsonStringField(manifest, "appId")) |value| {
        try writer.writeAll(",\"appId\":");
        try trace.writeJsonString(writer, value);
    }
    try writer.writeAll(",\"traceDir\":");
    try trace.writeJsonString(writer, trace_dir);
    if (jsonStringField(manifest, "eventsPath")) |value| {
        try writer.writeAll(",\"eventsPath\":");
        try trace.writeJsonString(writer, value);
    }
    if (jsonStringField(manifest, "artifactsDir")) |value| {
        try writer.writeAll(",\"artifactsDir\":");
        try trace.writeJsonString(writer, value);
    }
    if (jsonIntField(manifest, "durationMs")) |value| try writer.print(",\"durationMs\":{d}", .{value});
    if (jsonIntField(manifest, "eventCount")) |value| try writer.print(",\"eventCount\":{d}", .{value});
    if (jsonIntField(manifest, "snapshotCount")) |value| try writer.print(",\"snapshotCount\":{d}", .{value});
    if (jsonIntField(manifest, "failedStepIndex")) |value| try writer.print(",\"failedStepIndex\":{d}", .{value});
    if (jsonStringField(manifest, "error")) |value| {
        try writer.writeAll(",\"error\":");
        try trace.writeJsonString(writer, value);
    } else if (run_error) |err| {
        try writer.writeAll(",\"error\":");
        try trace.writeJsonString(writer, @errorName(err));
    }
    if (jsonStringField(manifest, "reportPath")) |value| {
        try writer.writeAll(",\"reportPath\":");
        try trace.writeJsonString(writer, value);
    }
    try writer.writeAll("}\n");
}

fn jsonStringField(object: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const value = object.get(key) orelse return null;
    if (value != .string) return null;
    return value.string;
}

fn jsonIntField(object: std.json.ObjectMap, key: []const u8) ?i64 {
    const value = object.get(key) orelse return null;
    return switch (value) {
        .integer => |actual| actual,
        else => null,
    };
}

fn runAndroidWithTrace(
    allocator: std.mem.Allocator,
    device: *android.AndroidDevice,
    script: scenario.Scenario,
    trace_dir: ?[]const u8,
    capture: trace.CaptureOptions,
) !void {
    if (trace_dir == null or !capture.capture_screen_recording) {
        return try runWithTrace(allocator, device, script, trace_dir, capture);
    }

    var trace_writer = try trace.TraceWriter.initWithOptions(allocator, trace_dir.?, capture);
    defer trace_writer.deinit();

    var recording = device.startScreenRecording("/sdcard/zmr-trace-screenrecord.mp4") catch null;
    defer if (recording) |*rec| {
        if (rec.stopAndPull(&trace_writer, "screenrecord.mp4")) |artifact_path| {
            allocator.free(artifact_path);
            trace_writer.recordEvent("trace.screenRecording", "{\"artifact\":\"artifacts/screenrecord.mp4\"}") catch {};
        } else |_| {}
        rec.deinit();
    };

    return try runner.runScenario(allocator, device, script, &trace_writer, .{});
}

fn runWithTrace(
    allocator: std.mem.Allocator,
    device: anytype,
    script: scenario.Scenario,
    trace_dir: ?[]const u8,
    capture: trace.CaptureOptions,
) !void {
    var trace_writer: ?trace.TraceWriter = null;
    if (trace_dir) |dir| {
        trace_writer = try trace.TraceWriter.initWithOptions(allocator, dir, capture);
    }
    defer if (trace_writer) |*tw| tw.deinit();

    if (trace_writer) |*tw| return try runner.runScenario(allocator, device, script, tw, .{});
    return try runner.runScenario(allocator, device, script, null, .{});
}

fn cmdReport(allocator: std.mem.Allocator, args: *std.process.ArgIterator) !void {
    const input_path = args.next() orelse return error.MissingReportInput;
    var out_path: ?[]const u8 = null;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--out")) {
            out_path = args.next() orelse return error.MissingReportOutput;
        } else {
            return error.UnknownFlag;
        }
    }

    const actual_out = out_path orelse return error.MissingReportOutput;
    try report.writeHtmlReport(allocator, input_path, actual_out);
    try std.fs.File.stdout().deprecatedWriter().print("wrote {s}\n", .{actual_out});
}

fn cmdExplain(allocator: std.mem.Allocator, args: *std.process.ArgIterator) !void {
    const trace_dir = args.next() orelse return error.MissingTraceDir;
    var json = false;
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--json")) {
            json = true;
        } else {
            return error.UnknownFlag;
        }
    }
    const stdout = std.fs.File.stdout().deprecatedWriter();
    if (json) return try report.writeTraceExplanationJson(allocator, trace_dir, stdout);
    try report.writeTraceExplanation(allocator, trace_dir, stdout);
}

fn cmdExport(allocator: std.mem.Allocator, args: *std.process.ArgIterator) !void {
    const trace_dir = args.next() orelse return error.MissingTraceDir;
    var out_path: ?[]const u8 = null;
    var redact = false;
    var omit_screenshots = false;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--out")) {
            out_path = args.next() orelse return error.MissingTraceBundleOutput;
        } else if (std.mem.eql(u8, arg, "--redact")) {
            redact = true;
        } else if (std.mem.eql(u8, arg, "--omit-screenshots")) {
            redact = true;
            omit_screenshots = true;
        } else {
            return error.UnknownFlag;
        }
    }

    const actual_out = out_path orelse return error.MissingTraceBundleOutput;
    try bundle.exportTraceBundleWithOptions(allocator, trace_dir, actual_out, .{
        .redact = redact,
        .omit_screenshots = omit_screenshots,
    });
    try std.fs.File.stdout().deprecatedWriter().print("wrote {s}\n", .{actual_out});
}

fn cmdServe(allocator: std.mem.Allocator, args: *std.process.ArgIterator) !void {
    var raw = RawServeOptions{};
    var adb_path: []const u8 = "adb";
    var xcrun_path: []const u8 = "xcrun";
    var transport: []const u8 = "stdio";
    var port: u16 = 8765;
    var config_path: ?[]const u8 = null;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--device")) {
            raw.serial = args.next() orelse return error.MissingDeviceSerial;
        } else if (std.mem.eql(u8, arg, "--app-id")) {
            raw.app_id = args.next() orelse return error.MissingAppId;
        } else if (std.mem.eql(u8, arg, "--trace-dir")) {
            raw.trace_dir = args.next() orelse return error.MissingTraceDir;
        } else if (std.mem.eql(u8, arg, "--adb")) {
            adb_path = args.next() orelse return error.MissingAdbPath;
        } else if (std.mem.eql(u8, arg, "--android-shim")) {
            raw.android_shim_path = args.next() orelse return error.MissingAndroidShimPath;
        } else if (std.mem.eql(u8, arg, "--xcrun")) {
            xcrun_path = args.next() orelse return error.MissingXcrunPath;
        } else if (std.mem.eql(u8, arg, "--ios-shim")) {
            raw.ios_shim_path = args.next() orelse return error.MissingIosShimPath;
        } else if (std.mem.eql(u8, arg, "--platform")) {
            raw.platform = try parsePlatform(args.next() orelse return error.MissingPlatform);
        } else if (std.mem.eql(u8, arg, "--transport")) {
            transport = args.next() orelse return error.MissingTransport;
        } else if (std.mem.eql(u8, arg, "--port")) {
            const value = args.next() orelse return error.MissingPort;
            port = try std.fmt.parseInt(u16, value, 10);
        } else if (std.mem.eql(u8, arg, "--config")) {
            config_path = args.next() orelse return error.MissingConfigPath;
        } else {
            return error.UnknownFlag;
        }
    }

    var loaded_config = try loadConfigIfPresent(allocator, config_path);
    defer if (loaded_config) |*cfg| cfg.deinit(allocator);
    const resolved = if (loaded_config) |cfg| resolveServeOptions(raw, cfg) else resolveServeOptions(raw, null);
    const capture = if (loaded_config) |cfg| traceCaptureOptions(cfg) else trace.CaptureOptions{};

    switch (resolved.platform) {
        .android => {
            var device = try android.AndroidDevice.initWithShim(allocator, adb_path, resolved.serial, resolved.app_id, resolved.android_shim_path);
            defer device.deinit();
            try serveWithDevice(allocator, &device, transport, port, resolved.trace_dir, resolved.app_id, capture);
        },
        .ios => {
            var device = try ios.IosDevice.initWithShim(allocator, xcrun_path, resolved.serial, resolved.app_id, resolved.ios_shim_path);
            defer device.deinit();
            try serveWithDevice(allocator, &device, transport, port, resolved.trace_dir, resolved.app_id, capture);
        },
    }
}

fn serveWithDevice(
    allocator: std.mem.Allocator,
    device: anytype,
    transport: []const u8,
    port: u16,
    trace_dir: ?[]const u8,
    app_id: []const u8,
    capture: trace.CaptureOptions,
) !void {
    var trace_writer: ?trace.TraceWriter = null;
    if (trace_dir) |dir| {
        trace_writer = try trace.TraceWriter.initWithOptions(allocator, dir, capture);
        try trace_writer.?.startManifest("json-rpc session", app_id);
    }
    defer if (trace_writer) |*tw| tw.deinit();
    const live_trace = if (trace_writer) |*tw| tw else null;

    if (std.mem.eql(u8, transport, "stdio")) {
        try json_rpc.serveStdioWithTrace(allocator, device, live_trace);
    } else if (std.mem.eql(u8, transport, "tcp")) {
        try json_rpc.serveTcpWithTrace(allocator, device, port, live_trace);
    } else {
        return error.UnsupportedTransport;
    }
}

fn parsePlatform(value: []const u8) !Platform {
    if (std.mem.eql(u8, value, "android")) return .android;
    if (std.mem.eql(u8, value, "ios")) return .ios;
    return error.UnsupportedPlatform;
}

fn loadConfigIfPresent(allocator: std.mem.Allocator, explicit_path: ?[]const u8) !?config.Config {
    if (explicit_path) |path| return try config.parseFile(allocator, path);
    std.fs.cwd().access(default_config_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    return try config.parseFile(allocator, default_config_path);
}

fn resolveRunOptions(raw: RawRunOptions, cfg: ?config.Config) ResolvedRunOptions {
    const platform_cfg = platformConfigFor(raw.platform, cfg);
    return .{
        .scenario_path = raw.scenario_path orelse if (platform_cfg) |pc| pc.smoke_scenario else null,
        .serial = raw.serial orelse if (platform_cfg) |pc| pc.default_device else null,
        .trace_dir = raw.trace_dir orelse if (platform_cfg) |pc| pc.trace_dir else null,
        .app_id = raw.app_id orelse if (cfg) |value| value.app_id orelse "com.example.mobiletest" else "com.example.mobiletest",
        .android_shim_path = raw.android_shim_path orelse if (cfg) |value| value.tools.android_shim_path else null,
        .ios_shim_path = raw.ios_shim_path orelse if (cfg) |value| value.tools.ios_shim_path else null,
        .android_avd_name = raw.android_avd_name orelse if (platform_cfg) |pc| pc.avd_name else null,
        .android_restore_snapshot = raw.android_restore_snapshot orelse if (platform_cfg) |pc| pc.restore_snapshot else null,
        .android_create_avd_if_missing = raw.android_create_avd_if_missing orelse if (platform_cfg) |pc| pc.create_avd_if_missing else false,
        .android_avd_system_image = raw.android_avd_system_image orelse if (platform_cfg) |pc| pc.avd_system_image else null,
        .android_avd_device_profile = raw.android_avd_device_profile orelse if (platform_cfg) |pc| pc.avd_device_profile else null,
        .android_reset_before_run = raw.android_reset_before_run orelse if (platform_cfg) |pc| pc.reset_before_run else false,
        .android_wait_ready = raw.android_wait_ready orelse if (platform_cfg) |pc| pc.wait_ready else false,
        .platform = raw.platform,
    };
}

fn androidPreflightOptions(resolved: ResolvedRunOptions, adb_path: []const u8, emulator_path: []const u8, avdmanager_path: []const u8) ?android_emulator.PreflightOptions {
    const options = android_emulator.PreflightOptions{
        .adb_path = adb_path,
        .emulator_path = emulator_path,
        .avdmanager_path = avdmanager_path,
        .device_serial = resolved.serial,
        .avd_name = resolved.android_avd_name,
        .restore_snapshot = resolved.android_restore_snapshot,
        .create_avd_if_missing = resolved.android_create_avd_if_missing,
        .avd_system_image = resolved.android_avd_system_image,
        .avd_device_profile = resolved.android_avd_device_profile,
        .reset_before_run = resolved.android_reset_before_run,
        .wait_ready = resolved.android_wait_ready,
    };
    return if (android_emulator.hasWork(options)) options else null;
}

fn resolveServeOptions(raw: RawServeOptions, cfg: ?config.Config) ResolvedServeOptions {
    const platform_cfg = platformConfigFor(raw.platform, cfg);
    return .{
        .serial = raw.serial orelse if (platform_cfg) |pc| pc.default_device else null,
        .app_id = raw.app_id orelse if (cfg) |value| value.app_id orelse "com.example.mobiletest" else "com.example.mobiletest",
        .trace_dir = raw.trace_dir orelse if (platform_cfg) |pc| pc.trace_dir else null,
        .android_shim_path = raw.android_shim_path orelse if (cfg) |value| value.tools.android_shim_path else null,
        .ios_shim_path = raw.ios_shim_path orelse if (cfg) |value| value.tools.ios_shim_path else null,
        .platform = raw.platform,
    };
}

fn platformConfigFor(platform: Platform, cfg: ?config.Config) ?config.PlatformConfig {
    if (cfg) |value| {
        return switch (platform) {
            .android => value.android,
            .ios => value.ios,
        };
    }
    return null;
}

fn traceCaptureOptions(cfg: config.Config) trace.CaptureOptions {
    return .{
        .capture_screenshots = cfg.artifacts.screenshots,
        .capture_hierarchy = cfg.artifacts.hierarchy,
        .capture_logs = cfg.artifacts.logs,
        .capture_screen_recording = cfg.artifacts.screen_recording,
        .redaction = .{
            .denylist_text = cfg.redaction.denylist_text,
            .allowlist_text = cfg.redaction.allowlist_text,
            .denylist_resource_ids = cfg.redaction.denylist_resource_ids,
            .allowlist_resource_ids = cfg.redaction.allowlist_resource_ids,
        },
    };
}

fn writeDoctorText(writer: anytype, config_check: ?doctor.Check, checks: []const doctor.Check) !void {
    const healthy = doctorChecksHealthy(config_check, checks);
    if (config_check) |check| {
        try writer.print("{s}\t{s}\t{s}\n", .{ check.name, @tagName(check.status), check.detail });
        if (check.hint) |hint| {
            try writer.print("{s}-hint\t{s}\n", .{ check.name, hint });
        }
    }
    for (checks) |check| {
        try writer.print("{s}\t{s}\t{s}\n", .{ check.name, @tagName(check.status), check.detail });
        if (check.hint) |hint| {
            try writer.print("{s}-hint\t{s}\n", .{ check.name, hint });
        }
    }
    try writer.print("status\t{s}\n", .{if (healthy) "ok" else "needs-attention"});
}

fn writeDoctorJson(writer: anytype, config_check: ?doctor.Check, checks: []const doctor.Check) !void {
    const healthy = doctorChecksHealthy(config_check, checks);
    try writer.writeAll("{\"ok\":");
    try writer.writeAll(if (healthy) "true" else "false");
    try writer.writeAll(",\"checks\":[");
    var index: usize = 0;
    if (config_check) |check| {
        try writeDoctorCheckJson(writer, check);
        index += 1;
    }
    for (checks) |check| {
        if (index > 0) try writer.writeAll(",");
        try writeDoctorCheckJson(writer, check);
        index += 1;
    }
    try writer.writeAll("]}\n");
}

fn doctorChecksHealthy(config_check: ?doctor.Check, checks: []const doctor.Check) bool {
    var healthy = true;
    if (config_check) |check| {
        if (check.status != .ok) healthy = false;
    }
    for (checks) |check| {
        if (check.status != .ok) healthy = false;
    }
    return healthy;
}

fn writeDoctorCheckJson(writer: anytype, check: doctor.Check) !void {
    try writer.writeAll("{\"name\":");
    try trace.writeJsonString(writer, check.name);
    try writer.writeAll(",\"status\":");
    try trace.writeJsonString(writer, @tagName(check.status));
    if (check.error_code) |error_code| {
        try writer.writeAll(",\"errorCode\":");
        try trace.writeJsonString(writer, error_code);
    }
    try writer.writeAll(",\"detail\":");
    try trace.writeJsonString(writer, check.detail);
    if (check.hint) |hint| {
        try writer.writeAll(",\"hint\":");
        try trace.writeJsonString(writer, hint);
    }
    if (check.field_path) |field_path| {
        try writer.writeAll(",\"fieldPath\":");
        try trace.writeJsonString(writer, field_path);
    }
    try writer.writeAll("}");
}

fn writeValidationText(writer: anytype, path: []const u8, result: validation.Result) !void {
    if (result.ok) {
        try writer.print("{s}: ok ({s}, {d} steps)\n", .{ path, result.name.?, result.step_count });
    } else {
        try writer.print("{s}: invalid [{s}] {s}", .{ path, result.error_code.?, result.message.? });
        if (result.path) |field_path| {
            try writer.print(" at {s}", .{field_path});
        }
        if (result.line) |line| {
            try writer.print(" line {d}", .{line});
            if (result.column) |column| try writer.print(" column {d}", .{column});
        }
        try writer.writeAll("\n");
    }
}

fn writeValidationJson(writer: anytype, path: []const u8, result: validation.Result) !void {
    try writer.writeAll("{\"ok\":");
    try writer.writeAll(if (result.ok) "true" else "false");
    try writer.writeAll(",\"path\":");
    try trace.writeJsonString(writer, path);
    if (result.ok) {
        try writer.writeAll(",\"name\":");
        try trace.writeJsonString(writer, result.name.?);
        try writer.print(",\"stepCount\":{d}", .{result.step_count});
    } else {
        try writer.writeAll(",\"errorCode\":");
        try trace.writeJsonString(writer, result.error_code.?);
        try writer.writeAll(",\"message\":");
        try trace.writeJsonString(writer, result.message.?);
        if (result.path) |field_path| {
            try writer.writeAll(",\"fieldPath\":");
            try trace.writeJsonString(writer, field_path);
        }
        if (result.line) |line| try writer.print(",\"line\":{d}", .{line});
        if (result.column) |column| try writer.print(",\"column\":{d}", .{column});
    }
    try writer.writeAll("}\n");
}

fn usage() !void {
    const stdout = std.fs.File.stdout().deprecatedWriter();
    try stdout.writeAll(
        \\zmr - Zig Mobile Runner
        \\
        \\Commands:
        \\  zmr version [--json]
        \\  zmr schemas [--json]
        \\  zmr devices [--json] [--platform android|ios] [--adb <path>] [--xcrun <path>]
        \\  zmr doctor [--json] [--strict] [--config <path>] [--zig <path>] [--adb <path>] [--android-shim <path>] [--xcrun <path>] [--ios-shim <path>]
        \\  zmr validate <scenario.json> [--json]
        \\  zmr init [scenario.json] [--app-id <id>] [--force] [--json]
        \\  zmr init --app [--dir <app-root>] [--app-id <id>] [--force] [--json]
        \\  zmr import flow-yaml <flow.yaml> --out <scenario.json> [--name <name>] [--app-id <id>] [--force] [--json]
        \\  zmr run [scenario.json] [--json] [--config <path>] [--platform android|ios] [--device <serial>] [--app-id <id>] [--trace-dir <path>] [--android-avd <name>] [--create-avd-if-missing] [--avd-system-image <pkg>] [--avd-device <profile>] [--restore-snapshot <name>] [--reset-emulator] [--wait-emulator] [--screen-record] [--no-screen-record] [--adb <path>] [--emulator <path>] [--avdmanager <path>] [--android-shim <path>] [--xcrun <path>] [--ios-shim <path>]
        \\  zmr report <trace-or-benchmark-dir> --out <report.html>
        \\  zmr explain <trace-dir> [--json]
        \\  zmr export <trace-dir> --out <bundle.zmrtrace> [--redact] [--omit-screenshots]
        \\  zmr serve --transport stdio [--config <path>] [--platform android|ios] [--device <serial>] [--app-id <id>] [--trace-dir <path>] [--adb <path>] [--android-shim <path>] [--xcrun <path>] [--ios-shim <path>]
        \\  zmr serve --transport tcp [--port <port>] [--config <path>] [--platform android|ios] [--device <serial>] [--app-id <id>] [--trace-dir <path>] [--adb <path>] [--android-shim <path>] [--xcrun <path>] [--ios-shim <path>]
        \\
        \\Scenario actions: launch, stop, clearState, openLink, tap, typeText,
        \\eraseText, hideKeyboard, swipe, pressBack, waitVisible, waitNotVisible,
        \\waitAny, whenVisible, repeat, scrollUntilVisible, assertVisible,
        \\assertNotVisible, snapshot, sleep. Any step may use "optional": true.
        \\
    );
}

test {
    _ = android;
    _ = android_emulator;
    _ = bundle;
    _ = command;
    _ = config;
    _ = doctor;
    _ = errors;
    _ = fake_device;
    _ = ios;
    _ = ios_shim;
    _ = importer;
    _ = json_rpc;
    _ = report;
    _ = runner;
    _ = scaffold;
    _ = scenario;
    _ = selector;
    _ = trace;
    _ = types;
    _ = uiautomator;
    _ = validation;
    _ = version;
}

test "fake device can run a probe-style scenario" {
    const allocator = std.testing.allocator;
    const node = types.UiNode{
        .stable_id = try allocator.dupe(u8, "probe-node"),
        .class_name = try allocator.dupe(u8, "android.widget.TextView"),
        .text = try allocator.dupe(u8, "E2E auth probe"),
        .bounds = .{ .x = 10, .y = 20, .width = 100, .height = 40 },
    };
    const nodes = try allocator.alloc(types.UiNode, 1);
    nodes[0] = node;
    var snaps = try allocator.alloc(types.ObservationSnapshot, 1);
    snaps[0] = .{
        .id = try allocator.dupe(u8, "snapshot-1"),
        .timestamp_ms = 1,
        .nodes = nodes,
    };
    defer {
        snaps[0].deinit(allocator);
        allocator.free(snaps);
    }

    var fake = fake_device.FakeDevice.init(allocator, snaps);
    defer fake.deinit();

    const script_json =
        \\{
        \\  "name": "fake probe",
        \\  "steps": [
        \\    {"action": "openLink", "url": "exampleapp://e2e-auth?probe=1"},
        \\    {"action": "waitVisible", "selector": {"text": "E2E auth probe"}, "timeoutMs": 10}
        \\  ]
        \\}
    ;
    const script = try scenario.parseSlice(allocator, script_json);
    defer script.deinit(allocator);

    try runner.runScenario(allocator, &fake, script, null, .{ .settle_ms = 0, .poll_ms = 1, .default_timeout_ms = 10 });
    try std.testing.expectEqualStrings("exampleapp://e2e-auth?probe=1", fake.opened_link.?);
}

test "validation output includes field and source location diagnostics" {
    const allocator = std.testing.allocator;
    const result = validation.Result{
        .ok = false,
        .error_code = try allocator.dupe(u8, "scenario.invalid"),
        .message = try allocator.dupe(u8, "scenario is invalid"),
        .path = try allocator.dupe(u8, "$.steps"),
        .line = 3,
        .column = 3,
    };
    defer result.deinit(allocator);

    var text = std.ArrayList(u8).empty;
    defer text.deinit(allocator);
    try writeValidationText(text.writer(allocator), "bad.json", result);
    try std.testing.expectEqualStrings("bad.json: invalid [scenario.invalid] scenario is invalid at $.steps line 3 column 3\n", text.items);

    var json = std.ArrayList(u8).empty;
    defer json.deinit(allocator);
    try writeValidationJson(json.writer(allocator), "bad.json", result);
    try std.testing.expect(std.mem.indexOf(u8, json.items, "\"fieldPath\":\"$.steps\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json.items, "\"line\":3") != null);
    try std.testing.expect(std.mem.indexOf(u8, json.items, "\"column\":3") != null);
}

test "pilot scenario examples parse" {
    const allocator = std.testing.allocator;
    const probe = try scenario.parseFile(allocator, "examples/android-app-auth-probe.json");
    defer probe.deinit(allocator);
    try std.testing.expectEqualStrings("com.example.mobiletest", probe.app_id.?);
    try std.testing.expect(probe.steps.len > 0);

    const login = try scenario.parseFile(allocator, "examples/android-app-login-smoke.json");
    defer login.deinit(allocator);
    try std.testing.expectEqualStrings("com.example.mobiletest", login.app_id.?);
    try std.testing.expect(login.steps.len > probe.steps.len);

    const demo = try scenario.parseFile(allocator, "examples/demo-fake.json");
    defer demo.deinit(allocator);
    try std.testing.expectEqualStrings("com.example.mobiletest", demo.app_id.?);

    const android_shim_smoke = try scenario.parseFile(allocator, "examples/android-shim-smoke.json");
    defer android_shim_smoke.deinit(allocator);
    try std.testing.expectEqualStrings("com.example.mobiletest", android_shim_smoke.app_id.?);

    const ios_smoke = try scenario.parseFile(allocator, "examples/ios-smoke.json");
    defer ios_smoke.deinit(allocator);
    try std.testing.expectEqualStrings("com.example.mobiletest", ios_smoke.app_id.?);
    try std.testing.expectEqual(@as(usize, 3), ios_smoke.steps.len);

    const ios_shim_smoke = try scenario.parseFile(allocator, "examples/ios-shim-smoke.json");
    defer ios_shim_smoke.deinit(allocator);
    try std.testing.expectEqualStrings("com.example.mobiletest", ios_shim_smoke.app_id.?);
    try std.testing.expect(ios_shim_smoke.steps.len > ios_smoke.steps.len);
}

test "platform parser accepts supported values" {
    try std.testing.expectEqual(Platform.android, try parsePlatform("android"));
    try std.testing.expectEqual(Platform.ios, try parsePlatform("ios"));
    try std.testing.expectError(error.UnsupportedPlatform, parsePlatform("windows"));
}

test "run options apply app-local config defaults and let cli flags override" {
    const allocator = std.testing.allocator;
    const cfg_json =
        \\{
        \\  "schemaVersion": 1,
        \\  "appId": "com.example.config",
        \\  "android": {
        \\    "enabled": true,
        \\    "defaultDevice": "emulator-6000",
        \\    "smokeScenario": ".zmr/android-smoke.json",
        \\    "traceDir": "traces/from-config",
        \\    "avdName": "Small_Phone",
        \\    "restoreSnapshot": "zmr-clean",
        \\    "resetBeforeRun": true,
        \\    "waitReady": true,
        \\    "createAvdIfMissing": true,
        \\    "avdSystemImage": "system-images;android-35;google_apis;arm64-v8a",
        \\    "avdDeviceProfile": "pixel_6"
        \\  },
        \\  "ios": {
        \\    "enabled": true,
        \\    "defaultDevice": "booted",
        \\    "smokeScenario": ".zmr/ios-smoke.json",
        \\    "traceDir": "traces/ios"
        \\  },
        \\  "artifacts": {
        \\    "screenshots": false,
        \\    "hierarchy": false,
        \\    "logs": false,
        \\    "screenRecording": true
        \\  },
        \\  "tools": {
        \\    "androidShimPath": "./tests/fake-android-shim.sh",
        \\    "iosShimPath": "./tests/fake-ios-shim.sh"
        \\  }
        \\}
    ;
    var cfg = try config.parseSlice(allocator, cfg_json);
    defer cfg.deinit(allocator);

    const resolved = resolveRunOptions(.{
        .scenario_path = null,
        .serial = null,
        .trace_dir = null,
        .app_id = null,
        .platform = .android,
    }, cfg);

    try std.testing.expectEqualStrings(".zmr/android-smoke.json", resolved.scenario_path.?);
    try std.testing.expectEqualStrings("emulator-6000", resolved.serial.?);
    try std.testing.expectEqualStrings("traces/from-config", resolved.trace_dir.?);
    try std.testing.expectEqualStrings("com.example.config", resolved.app_id);
    try std.testing.expectEqualStrings("./tests/fake-android-shim.sh", resolved.android_shim_path.?);
    try std.testing.expectEqualStrings("./tests/fake-ios-shim.sh", resolved.ios_shim_path.?);
    try std.testing.expectEqualStrings("Small_Phone", resolved.android_avd_name.?);
    try std.testing.expectEqualStrings("zmr-clean", resolved.android_restore_snapshot.?);
    try std.testing.expect(resolved.android_create_avd_if_missing);
    try std.testing.expectEqualStrings("system-images;android-35;google_apis;arm64-v8a", resolved.android_avd_system_image.?);
    try std.testing.expectEqualStrings("pixel_6", resolved.android_avd_device_profile.?);
    try std.testing.expect(resolved.android_reset_before_run);
    try std.testing.expect(resolved.android_wait_ready);

    const capture = traceCaptureOptions(cfg);
    try std.testing.expect(!capture.capture_screenshots);
    try std.testing.expect(!capture.capture_hierarchy);
    try std.testing.expect(!capture.capture_logs);
    try std.testing.expect(capture.capture_screen_recording);

    const overridden = resolveRunOptions(.{
        .scenario_path = "custom.json",
        .serial = "device-1",
        .trace_dir = "traces/custom",
        .app_id = "com.example.cli",
        .android_shim_path = "./custom-android-shim",
        .ios_shim_path = "./custom-ios-shim",
        .platform = .android,
    }, cfg);

    try std.testing.expectEqualStrings("custom.json", overridden.scenario_path.?);
    try std.testing.expectEqualStrings("device-1", overridden.serial.?);
    try std.testing.expectEqualStrings("traces/custom", overridden.trace_dir.?);
    try std.testing.expectEqualStrings("com.example.cli", overridden.app_id);
    try std.testing.expectEqualStrings("./custom-android-shim", overridden.android_shim_path.?);
    try std.testing.expectEqualStrings("./custom-ios-shim", overridden.ios_shim_path.?);

    const serve_resolved = resolveServeOptions(.{
        .serial = null,
        .app_id = null,
        .trace_dir = null,
        .platform = .android,
    }, cfg);
    try std.testing.expectEqualStrings("emulator-6000", serve_resolved.serial.?);
    try std.testing.expectEqualStrings("traces/from-config", serve_resolved.trace_dir.?);
    try std.testing.expectEqualStrings("com.example.config", serve_resolved.app_id);

    const serve_overridden = resolveServeOptions(.{
        .serial = "device-2",
        .app_id = "com.example.serve",
        .trace_dir = "traces/serve",
        .platform = .android,
    }, cfg);
    try std.testing.expectEqualStrings("device-2", serve_overridden.serial.?);
    try std.testing.expectEqualStrings("traces/serve", serve_overridden.trace_dir.?);
    try std.testing.expectEqualStrings("com.example.serve", serve_overridden.app_id);
}

test "public schema files parse as json" {
    const allocator = std.testing.allocator;
    for (public_schemas) |schema_info| {
        const content = try std.fs.cwd().readFileAlloc(allocator, schema_info.path, 1024 * 1024);
        defer allocator.free(content);
        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, content, .{});
        defer parsed.deinit();
        try std.testing.expect(parsed.value == .object);
    }
}
