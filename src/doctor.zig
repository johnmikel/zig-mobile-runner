const std = @import("std");
const android = @import("android.zig");
const command = @import("command.zig");
const ios = @import("ios.zig");
const validation = @import("validation.zig");

pub const Status = enum {
    ok,
    warning,
    missing,
};

pub const Check = struct {
    name: []const u8,
    status: Status,
    detail: []const u8,
    error_code: ?[]const u8 = null,
    field_path: ?[]const u8 = null,
    hint: ?[]const u8 = null,

    pub fn deinit(self: Check, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.detail);
        if (self.error_code) |error_code| allocator.free(error_code);
        if (self.field_path) |field_path| allocator.free(field_path);
        if (self.hint) |hint| allocator.free(hint);
    }
};

pub const Options = struct {
    zig_path: []const u8 = "zig",
    adb_path: []const u8 = "adb",
    android_shim_path: ?[]const u8 = null,
    android_smoke_scenario: ?[]const u8 = null,
    xcrun_path: []const u8 = "xcrun",
    ios_shim_path: ?[]const u8 = null,
    ios_smoke_scenario: ?[]const u8 = null,
};

pub fn checkConfigLoaded(allocator: std.mem.Allocator, path: []const u8) !Check {
    return .{
        .name = try allocator.dupe(u8, "config"),
        .status = .ok,
        .detail = try allocator.dupe(u8, path),
    };
}

pub fn checkConfigError(allocator: std.mem.Allocator, path: []const u8, err: anyerror, field_path: ?[]const u8) !Check {
    const status: Status = if (err == error.FileNotFound) .missing else .warning;
    return .{
        .name = try allocator.dupe(u8, "config"),
        .status = status,
        .detail = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ path, @errorName(err) }),
        .error_code = try allocator.dupe(u8, configErrorCode(err)),
        .field_path = if (field_path) |value| try allocator.dupe(u8, value) else null,
        .hint = try hintForCheck(allocator, "config", status),
    };
}

fn configErrorCode(err: anyerror) []const u8 {
    return switch (err) {
        error.FileNotFound => "config.file_not_found",
        error.ConfigMustBeObject => "config.must_be_object",
        error.MissingConfigSchemaVersion => "config.missing_schema_version",
        error.ConfigSchemaVersionMustBeInteger => "config.schema_version_type",
        error.UnsupportedConfigVersion => "config.unsupported_version",
        error.ConfigUnknownField => "config.unknown_field",
        error.ConfigPlatformMustBeObject,
        error.ConfigToolsMustBeObject,
        error.ConfigArtifactsMustBeObject,
        error.ConfigRedactionMustBeObject,
        error.ConfigScriptsMustBeObject,
        error.ConfigFieldMustBeBool,
        error.ConfigFieldMustBeString,
        error.ConfigFieldMustBeStringArray,
        => "config.field_type",
        error.ConfigFieldMustBeNonEmptyString => "config.empty_string",
        else => "config.invalid",
    };
}

pub fn run(allocator: std.mem.Allocator, options: Options) ![]Check {
    var checks = std.ArrayList(Check).empty;
    errdefer {
        for (checks.items) |check| check.deinit(allocator);
        checks.deinit(allocator);
    }

    try checks.append(allocator, try checkCommand(allocator, "zig", &.{ options.zig_path, "version" }));
    try checks.append(allocator, try checkCommand(allocator, "adb", &.{ options.adb_path, "version" }));
    try checks.append(allocator, try checkAndroidDevices(allocator, options.adb_path));
    if (options.android_shim_path) |path| try checks.append(allocator, try checkPath(allocator, "android-shim", path));
    if (options.android_smoke_scenario) |path| try checks.append(allocator, try checkScenarioPath(allocator, "android-smoke-scenario", path));
    try checks.append(allocator, try checkCommand(allocator, "xcrun", &.{ options.xcrun_path, "--version" }));
    try checks.append(allocator, try checkIosSimulators(allocator, options.xcrun_path));
    if (options.ios_shim_path) |path| try checks.append(allocator, try checkPath(allocator, "ios-shim", path));
    if (options.ios_smoke_scenario) |path| try checks.append(allocator, try checkScenarioPath(allocator, "ios-smoke-scenario", path));

    return try checks.toOwnedSlice(allocator);
}

fn checkPath(allocator: std.mem.Allocator, name: []const u8, path: []const u8) !Check {
    std.fs.cwd().access(path, .{ .mode = .read_only }) catch |err| {
        return .{
            .name = try allocator.dupe(u8, name),
            .status = .missing,
            .error_code = try allocator.dupe(u8, setupErrorCode(name, .missing)),
            .detail = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ path, @errorName(err) }),
            .hint = try hintForCheck(allocator, name, .missing),
        };
    };
    return .{
        .name = try allocator.dupe(u8, name),
        .status = .ok,
        .detail = try allocator.dupe(u8, path),
    };
}

fn checkScenarioPath(allocator: std.mem.Allocator, name: []const u8, path: []const u8) !Check {
    const result = try validation.validateFile(allocator, path);
    defer result.deinit(allocator);

    if (result.ok) {
        return .{
            .name = try allocator.dupe(u8, name),
            .status = .ok,
            .detail = try std.fmt.allocPrint(allocator, "{s}: ok ({s}, {d} steps)", .{ path, result.name.?, result.step_count }),
        };
    }

    const status: Status = if (result.error_code != null and std.mem.eql(u8, result.error_code.?, "scenario.file_not_found")) .missing else .warning;
    const code = result.error_code orelse "scenario.invalid";
    return .{
        .name = try allocator.dupe(u8, name),
        .status = status,
        .detail = try scenarioValidationDetail(allocator, path, result),
        .error_code = try allocator.dupe(u8, code),
        .hint = try hintForCheck(allocator, name, status),
    };
}

fn scenarioValidationDetail(allocator: std.mem.Allocator, path: []const u8, result: validation.Result) ![]const u8 {
    const code = result.error_code orelse "scenario.invalid";
    const message = result.message orelse "scenario is invalid";
    if (result.path) |field_path| {
        if (result.line) |line| {
            if (result.column) |column| {
                return try std.fmt.allocPrint(allocator, "{s}: invalid [{s}] {s} at {s} line {d} column {d}", .{ path, code, message, field_path, line, column });
            }
        }
        return try std.fmt.allocPrint(allocator, "{s}: invalid [{s}] {s} at {s}", .{ path, code, message, field_path });
    }
    if (result.line) |line| {
        if (result.column) |column| {
            return try std.fmt.allocPrint(allocator, "{s}: invalid [{s}] {s} line {d} column {d}", .{ path, code, message, line, column });
        }
    }
    return try std.fmt.allocPrint(allocator, "{s}: invalid [{s}] {s}", .{ path, code, message });
}

fn checkAndroidDevices(allocator: std.mem.Allocator, adb_path: []const u8) !Check {
    const devices = android.listDevices(allocator, adb_path) catch |err| {
        return .{
            .name = try allocator.dupe(u8, "android-devices"),
            .status = .missing,
            .error_code = try allocator.dupe(u8, "setup.android.devices_unavailable"),
            .detail = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ adb_path, @errorName(err) }),
            .hint = try hintForCheck(allocator, "android-devices", .missing),
        };
    };
    defer {
        for (devices) |device| device.deinit(allocator);
        allocator.free(devices);
    }
    if (devices.len == 0) {
        return .{
            .name = try allocator.dupe(u8, "android-devices"),
            .status = .warning,
            .error_code = try allocator.dupe(u8, "setup.android.no_devices"),
            .detail = try allocator.dupe(u8, "0 Android device(s)"),
            .hint = try hintForCheck(allocator, "android-devices", .warning),
        };
    }
    return .{
        .name = try allocator.dupe(u8, "android-devices"),
        .status = .ok,
        .detail = try std.fmt.allocPrint(allocator, "{d} Android device(s)", .{devices.len}),
    };
}

fn checkIosSimulators(allocator: std.mem.Allocator, xcrun_path: []const u8) !Check {
    const devices = ios.listDevices(allocator, xcrun_path) catch |err| {
        return .{
            .name = try allocator.dupe(u8, "ios-simulators"),
            .status = .missing,
            .error_code = try allocator.dupe(u8, "setup.ios.simulators_unavailable"),
            .detail = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ xcrun_path, @errorName(err) }),
            .hint = try hintForCheck(allocator, "ios-simulators", .missing),
        };
    };
    defer {
        for (devices) |device| device.deinit(allocator);
        allocator.free(devices);
    }
    if (devices.len == 0) {
        return .{
            .name = try allocator.dupe(u8, "ios-simulators"),
            .status = .warning,
            .error_code = try allocator.dupe(u8, "setup.ios.no_booted_simulators"),
            .detail = try allocator.dupe(u8, "0 booted iOS simulator(s)"),
            .hint = try hintForCheck(allocator, "ios-simulators", .warning),
        };
    }
    return .{
        .name = try allocator.dupe(u8, "ios-simulators"),
        .status = .ok,
        .detail = try std.fmt.allocPrint(allocator, "{d} booted iOS simulator(s)", .{devices.len}),
    };
}

pub fn checkCommand(allocator: std.mem.Allocator, name: []const u8, argv: []const []const u8) !Check {
    const result = command.run(allocator, argv, 1024 * 1024) catch |err| {
        return .{
            .name = try allocator.dupe(u8, name),
            .status = .missing,
            .error_code = try allocator.dupe(u8, setupErrorCode(name, .missing)),
            .detail = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ argv[0], @errorName(err) }),
            .hint = try hintForCheck(allocator, name, .missing),
        };
    };
    defer result.deinit(allocator);

    if (result.term == .Exited and result.term.Exited == 0) {
        return .{
            .name = try allocator.dupe(u8, name),
            .status = .ok,
            .detail = try firstLine(allocator, result.stdout),
        };
    }

    const code = if (result.term == .Exited) result.term.Exited else 255;
    return .{
        .name = try allocator.dupe(u8, name),
        .status = .warning,
        .error_code = try allocator.dupe(u8, setupErrorCode(name, .warning)),
        .detail = try std.fmt.allocPrint(allocator, "exit {d}: {s}", .{ code, std.mem.trim(u8, result.stderr, " \t\r\n") }),
        .hint = try hintForCheck(allocator, name, .warning),
    };
}

fn setupErrorCode(name: []const u8, status: Status) []const u8 {
    if (std.mem.eql(u8, name, "zig")) return if (status == .missing) "setup.zig.not_found" else "setup.zig.command_failed";
    if (std.mem.eql(u8, name, "adb")) return if (status == .missing) "setup.adb.not_found" else "setup.adb.command_failed";
    if (std.mem.eql(u8, name, "xcrun")) return if (status == .missing) "setup.xcrun.not_found" else "setup.xcrun.command_failed";
    if (std.mem.eql(u8, name, "android-shim")) return if (status == .missing) "setup.android_shim.not_found" else "setup.android_shim.command_failed";
    if (std.mem.eql(u8, name, "ios-shim")) return if (status == .missing) "setup.ios_shim.not_found" else "setup.ios_shim.command_failed";
    return if (status == .missing) "setup.tool.not_found" else "setup.tool.command_failed";
}

fn hintForCheck(allocator: std.mem.Allocator, name: []const u8, status: Status) !?[]const u8 {
    if (status == .ok) return null;
    const hint =
        if (std.mem.eql(u8, name, "zig"))
            "Install Zig 0.15.2 or newer, ensure it is on PATH, then run zmr doctor again."
        else if (std.mem.eql(u8, name, "adb"))
            "Install Android SDK Platform Tools, ensure adb is on PATH, then run adb devices."
        else if (std.mem.eql(u8, name, "android-devices"))
            "Start an emulator or connect a device, confirm adb devices shows it, then pass --device when running scenarios."
        else if (std.mem.eql(u8, name, "config"))
            "Fix the config file or regenerate it with npx zmr-wizard, then run zmr doctor --config again."
        else if (std.mem.eql(u8, name, "android-shim"))
            "Run npx zmr-install-android-shim in the app repo or update tools.androidShimPath in .zmr/config.json."
        else if (std.mem.eql(u8, name, "android-smoke-scenario"))
            if (status == .warning)
                "Run zmr validate on the configured Android smoke scenario, fix the reported issue, or update android.smokeScenario in .zmr/config.json."
            else
                "Run npx zmr-wizard, create the Android smoke scenario, or update android.smokeScenario in .zmr/config.json."
        else if (std.mem.eql(u8, name, "xcrun"))
            "Install Xcode command line tools, run xcode-select --install if needed, then run xcrun --version."
        else if (std.mem.eql(u8, name, "ios-simulators"))
            "Boot an iOS simulator with Xcode or xcrun simctl boot, then run xcrun simctl list devices booted."
        else if (std.mem.eql(u8, name, "ios-shim"))
            "Run npx zmr-install-ios-shim in the app repo or update tools.iosShimPath in .zmr/config.json."
        else if (std.mem.eql(u8, name, "ios-smoke-scenario"))
            if (status == .warning)
                "Run zmr validate on the configured iOS smoke scenario, fix the reported issue, or update ios.smokeScenario in .zmr/config.json."
            else
                "Run npx zmr-wizard, create the iOS smoke scenario, or update ios.smokeScenario in .zmr/config.json."
        else
            "Run the command manually, fix the reported setup issue, then run zmr doctor again.";
    return try allocator.dupe(u8, hint);
}

fn firstLine(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    const trimmed = std.mem.trim(u8, value, " \t\r\n");
    const end = std.mem.indexOfScalar(u8, trimmed, '\n') orelse trimmed.len;
    return try allocator.dupe(u8, trimmed[0..end]);
}

test "doctor command check reports ok warning and missing" {
    const allocator = std.testing.allocator;

    const ok = try checkCommand(allocator, "ok", &.{ "/bin/sh", "-c", "printf ready" });
    defer ok.deinit(allocator);
    try std.testing.expectEqual(Status.ok, ok.status);
    try std.testing.expectEqualStrings("ready", ok.detail);

    const warning = try checkCommand(allocator, "warning", &.{ "/bin/sh", "-c", "printf bad >&2; exit 7" });
    defer warning.deinit(allocator);
    try std.testing.expectEqual(Status.warning, warning.status);
    try std.testing.expect(std.mem.indexOf(u8, warning.detail, "exit 7") != null);

    const missing = try checkCommand(allocator, "missing", &.{"/definitely/not/zmr-tool"});
    defer missing.deinit(allocator);
    try std.testing.expectEqual(Status.missing, missing.status);
    try std.testing.expectEqualStrings("setup.tool.not_found", missing.error_code.?);
}

test "doctor checks include remediation hints for actionable failures" {
    const allocator = std.testing.allocator;

    const ok = try checkCommand(allocator, "zig", &.{ "/bin/sh", "-c", "printf ready" });
    defer ok.deinit(allocator);
    try std.testing.expect(ok.hint == null);

    const warning = try checkCommand(allocator, "zig", &.{ "/bin/sh", "-c", "printf bad >&2; exit 7" });
    defer warning.deinit(allocator);
    try std.testing.expect(warning.hint != null);
    try std.testing.expectEqualStrings("setup.zig.command_failed", warning.error_code.?);
    try std.testing.expect(std.mem.indexOf(u8, warning.hint.?, "Zig") != null);

    const missing = try checkCommand(allocator, "adb", &.{"/definitely/not/zmr-tool"});
    defer missing.deinit(allocator);
    try std.testing.expect(missing.hint != null);
    try std.testing.expectEqualStrings("setup.adb.not_found", missing.error_code.?);
    try std.testing.expect(std.mem.indexOf(u8, missing.hint.?, "Android SDK Platform Tools") != null);
}

test "doctor config errors include stable codes and field paths" {
    const allocator = std.testing.allocator;

    const check = try checkConfigError(allocator, ".zmr/config.json", error.ConfigFieldMustBeNonEmptyString, "$.scripts.android");
    defer check.deinit(allocator);

    try std.testing.expectEqual(Status.warning, check.status);
    try std.testing.expectEqualStrings("config.empty_string", check.error_code.?);
    try std.testing.expectEqualStrings("$.scripts.android", check.field_path.?);
    try std.testing.expect(check.hint != null);
}

test "doctor run reports fake device counts" {
    const allocator = std.testing.allocator;
    const checks = try run(allocator, .{
        .zig_path = "zig",
        .adb_path = "./tests/fake-adb.sh",
        .xcrun_path = "./tests/fake-xcrun.sh",
    });
    defer {
        for (checks) |check| check.deinit(allocator);
        allocator.free(checks);
    }

    try std.testing.expectEqual(@as(usize, 5), checks.len);
    try std.testing.expectEqualStrings("1 Android device(s)", checks[2].detail);
    try std.testing.expectEqualStrings("1 booted iOS simulator(s)", checks[4].detail);
}

test "doctor warns when no mobile devices are ready" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var adb_file = try tmp.dir.createFile("fake-adb-empty.sh", .{ .truncate = true });
    try adb_file.writeAll(
        \\#!/usr/bin/env bash
        \\set -euo pipefail
        \\case "${1:-}" in
        \\  version) printf 'Android Debug Bridge version 1.0.41\n' ;;
        \\  devices) printf 'List of devices attached\n' ;;
        \\  *) exit 2 ;;
        \\esac
        \\
    );
    try adb_file.chmod(0o755);
    adb_file.close();

    var xcrun_file = try tmp.dir.createFile("fake-xcrun-empty.sh", .{ .truncate = true });
    try xcrun_file.writeAll(
        \\#!/usr/bin/env bash
        \\set -euo pipefail
        \\if [[ "${1:-}" == "--version" ]]; then
        \\  printf 'xcrun version 70\n'
        \\  exit 0
        \\fi
        \\if [[ "${1:-}" == "simctl" && "${2:-}" == "list" && "${3:-}" == "devices" && "${4:-}" == "--json" ]]; then
        \\  printf '{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-5":[]}}\n'
        \\  exit 0
        \\fi
        \\exit 2
        \\
    );
    try xcrun_file.chmod(0o755);
    xcrun_file.close();

    const adb_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/fake-adb-empty.sh", .{tmp.sub_path});
    defer allocator.free(adb_path);
    const xcrun_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/fake-xcrun-empty.sh", .{tmp.sub_path});
    defer allocator.free(xcrun_path);

    const checks = try run(allocator, .{
        .zig_path = "zig",
        .adb_path = adb_path,
        .xcrun_path = xcrun_path,
    });
    defer {
        for (checks) |check| check.deinit(allocator);
        allocator.free(checks);
    }

    try std.testing.expectEqual(Status.warning, checks[2].status);
    try std.testing.expectEqualStrings("setup.android.no_devices", checks[2].error_code.?);
    try std.testing.expectEqualStrings("0 Android device(s)", checks[2].detail);
    try std.testing.expect(checks[2].hint != null);

    try std.testing.expectEqual(Status.warning, checks[4].status);
    try std.testing.expectEqualStrings("setup.ios.no_booted_simulators", checks[4].error_code.?);
    try std.testing.expectEqualStrings("0 booted iOS simulator(s)", checks[4].detail);
    try std.testing.expect(checks[4].hint != null);
}

test "doctor reports configured ios shim path" {
    const allocator = std.testing.allocator;
    const checks = try run(allocator, .{
        .zig_path = "zig",
        .adb_path = "./tests/fake-adb.sh",
        .xcrun_path = "./tests/fake-xcrun.sh",
        .ios_shim_path = "./tests/fake-ios-shim.sh",
    });
    defer {
        for (checks) |check| check.deinit(allocator);
        allocator.free(checks);
    }

    try std.testing.expectEqual(@as(usize, 6), checks.len);
    try std.testing.expectEqualStrings("ios-shim", checks[5].name);
    try std.testing.expectEqual(Status.ok, checks[5].status);
}

test "doctor reports configured android shim path" {
    const allocator = std.testing.allocator;
    const checks = try run(allocator, .{
        .zig_path = "zig",
        .adb_path = "./tests/fake-adb.sh",
        .android_shim_path = "./tests/fake-android-shim.sh",
        .xcrun_path = "./tests/fake-xcrun.sh",
    });
    defer {
        for (checks) |check| check.deinit(allocator);
        allocator.free(checks);
    }

    try std.testing.expectEqual(@as(usize, 6), checks.len);
    try std.testing.expectEqualStrings("android-shim", checks[3].name);
    try std.testing.expectEqual(Status.ok, checks[3].status);
}

test "doctor reports configured smoke scenario paths" {
    const allocator = std.testing.allocator;
    const checks = try run(allocator, .{
        .zig_path = "zig",
        .adb_path = "./tests/fake-adb.sh",
        .android_smoke_scenario = "examples/demo-fake.json",
        .xcrun_path = "./tests/fake-xcrun.sh",
        .ios_smoke_scenario = "./definitely-missing-ios-smoke.json",
    });
    defer {
        for (checks) |check| check.deinit(allocator);
        allocator.free(checks);
    }

    try std.testing.expectEqual(@as(usize, 7), checks.len);
    try std.testing.expectEqualStrings("android-smoke-scenario", checks[3].name);
    try std.testing.expectEqual(Status.ok, checks[3].status);
    try std.testing.expectEqualStrings("ios-smoke-scenario", checks[6].name);
    try std.testing.expectEqual(Status.missing, checks[6].status);
    try std.testing.expect(checks[6].hint != null);
    try std.testing.expect(std.mem.indexOf(u8, checks[6].hint.?, "smokeScenario") != null);
}

test "doctor warns when configured smoke scenario is invalid" {
    const allocator = std.testing.allocator;
    const path = "zig-cache/test-doctor-invalid-smoke.json";
    try std.fs.cwd().makePath("zig-cache");
    try std.fs.cwd().writeFile(.{ .sub_path = path, .data = "{\n  \"name\": \"bad\",\n  \"steps\": \"nope\"\n}\n" });
    defer std.fs.cwd().deleteFile(path) catch {};

    const checks = try run(allocator, .{
        .zig_path = "zig",
        .adb_path = "./tests/fake-adb.sh",
        .android_smoke_scenario = path,
        .xcrun_path = "./tests/fake-xcrun.sh",
    });
    defer {
        for (checks) |check| check.deinit(allocator);
        allocator.free(checks);
    }

    try std.testing.expectEqualStrings("android-smoke-scenario", checks[3].name);
    try std.testing.expectEqual(Status.warning, checks[3].status);
    try std.testing.expect(std.mem.indexOf(u8, checks[3].detail, "scenario.invalid") != null);
    try std.testing.expect(checks[3].hint != null);
    try std.testing.expect(std.mem.indexOf(u8, checks[3].hint.?, "zmr validate") != null);
}
