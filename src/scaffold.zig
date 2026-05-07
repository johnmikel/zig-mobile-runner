const std = @import("std");

pub fn writeStarterScenario(
    allocator: std.mem.Allocator,
    path: []const u8,
    app_id: []const u8,
    force: bool,
) !void {
    if (!force) {
        std.fs.cwd().access(path, .{}) catch |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        };
        if (std.fs.cwd().access(path, .{})) |_| return error.PathAlreadyExists else |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        }
    }

    if (std.fs.path.dirname(path)) |parent| {
        if (parent.len > 0) try std.fs.cwd().makePath(parent);
    }

    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    var buffer: [4096]u8 = undefined;
    var file_writer = file.writer(&buffer);
    const writer = &file_writer.interface;
    try writer.writeAll(
        \\{
        \\  "name": "Starter mobile smoke",
        \\  "appId": "
    );
    try writeJsonStringContent(writer, app_id);
    try writer.writeAll(
        \\",
        \\  "steps": [
        \\    { "action": "launch" },
        \\    { "action": "snapshot" }
        \\  ]
        \\}
        \\
    );
    try writer.flush();
    _ = allocator;
}

pub fn writeAppScaffold(
    allocator: std.mem.Allocator,
    dir: []const u8,
    app_id: []const u8,
    force: bool,
) !void {
    const zmr_dir = try std.fs.path.join(allocator, &.{ dir, ".zmr" });
    defer allocator.free(zmr_dir);
    try std.fs.cwd().makePath(zmr_dir);

    const config_path = try std.fs.path.join(allocator, &.{ zmr_dir, "config.json" });
    defer allocator.free(config_path);
    const android_path = try std.fs.path.join(allocator, &.{ zmr_dir, "android-smoke.json" });
    defer allocator.free(android_path);
    const ios_path = try std.fs.path.join(allocator, &.{ zmr_dir, "ios-smoke.json" });
    defer allocator.free(ios_path);

    try writeAppConfig(config_path, app_id, force);
    try writePlatformSmoke(android_path, "Android smoke", app_id, force);
    try writePlatformSmoke(ios_path, "iOS smoke", app_id, force);
    try ensureTraceGitignore(allocator, dir);
}

fn writeAppConfig(path: []const u8, app_id: []const u8, force: bool) !void {
    var file = try createOutputFile(path, force);
    defer file.close();
    var buffer: [8192]u8 = undefined;
    var file_writer = file.writer(&buffer);
    const writer = &file_writer.interface;
    try writer.writeAll(
        \\{
        \\  "schemaVersion": 1,
        \\  "appId": "
    );
    try writeJsonStringContent(writer, app_id);
    try writer.writeAll(
        \\",
        \\  "android": {
        \\    "enabled": true,
        \\    "defaultDevice": "emulator-5554",
        \\    "smokeScenario": ".zmr/android-smoke.json",
        \\    "traceDir": "traces/zmr-android"
        \\  },
        \\  "ios": {
        \\    "enabled": true,
        \\    "defaultDevice": "booted",
        \\    "smokeScenario": ".zmr/ios-smoke.json",
        \\    "traceDir": "traces/zmr-ios"
        \\  },
        \\  "artifacts": {
        \\    "screenshots": true,
        \\    "hierarchy": true,
        \\    "logs": true,
        \\    "screenRecording": false
        \\  },
        \\  "scripts": {
        \\    "doctor": "zmr doctor --strict --json --config .zmr/config.json",
        \\    "android": "zmr run .zmr/android-smoke.json --device emulator-5554 --trace-dir traces/zmr-android",
        \\    "ios": "zmr run .zmr/ios-smoke.json --platform ios --device booted --trace-dir traces/zmr-ios",
        \\    "pilotGate": "zmr-pilot-gate --android --ios --android-app-root . --ios-app-path ./build/Debug-iphonesimulator/Sample.app --runs 20 --min-pass-rate 100 --max-failures 0",
        \\    "serve": "zmr serve --transport stdio --device emulator-5554 --app-id 
    );
    try writeJsonStringContent(writer, app_id);
    try writer.writeAll(
        \\"
        \\  }
        \\}
        \\
    );
    try writer.flush();
}

fn writePlatformSmoke(path: []const u8, name: []const u8, app_id: []const u8, force: bool) !void {
    var file = try createOutputFile(path, force);
    defer file.close();
    var buffer: [4096]u8 = undefined;
    var file_writer = file.writer(&buffer);
    const writer = &file_writer.interface;
    try writer.writeAll(
        \\{
        \\  "name": "
    );
    try writeJsonStringContent(writer, name);
    try writer.writeAll(
        \\",
        \\  "appId": "
    );
    try writeJsonStringContent(writer, app_id);
    try writer.writeAll(
        \\",
        \\  "steps": [
        \\    { "action": "launch" },
        \\    { "action": "snapshot" }
        \\  ]
        \\}
        \\
    );
    try writer.flush();
}

fn createOutputFile(path: []const u8, force: bool) !std.fs.File {
    if (std.fs.path.dirname(path)) |parent| {
        if (parent.len > 0) try std.fs.cwd().makePath(parent);
    }
    if (!force) return try std.fs.cwd().createFile(path, .{ .exclusive = true });
    return try std.fs.cwd().createFile(path, .{ .truncate = true });
}

fn ensureTraceGitignore(allocator: std.mem.Allocator, dir: []const u8) !void {
    const path = try std.fs.path.join(allocator, &.{ dir, ".gitignore" });
    defer allocator.free(path);

    const existing = std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => "",
        else => return err,
    };
    const had_existing_file = existing.ptr != "".ptr;
    defer if (had_existing_file) allocator.free(existing);

    if (std.mem.indexOf(u8, existing, "traces/") != null) return;

    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    var buffer: [4096]u8 = undefined;
    var file_writer = file.writer(&buffer);
    const writer = &file_writer.interface;
    if (existing.len > 0) {
        try writer.writeAll(existing);
        if (!std.mem.endsWith(u8, existing, "\n")) try writer.writeAll("\n");
        try writer.writeAll("\n");
    }
    try writer.writeAll(
        \\# ZMR local run artifacts
        \\traces/
        \\
    );
    try writer.flush();
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

test "starter scenario scaffolder writes a valid scenario and protects existing files" {
    const allocator = std.testing.allocator;
    const dir = "zig-cache-test-scaffold";
    std.fs.cwd().deleteTree(dir) catch {};
    defer std.fs.cwd().deleteTree(dir) catch {};
    try std.fs.cwd().makePath(dir);

    const path = dir ++ "/scenario.json";
    try writeStarterScenario(allocator, path, "com.example.mobiletest", false);
    try std.testing.expectError(error.PathAlreadyExists, writeStarterScenario(allocator, path, "com.example.mobiletest", false));
    try writeStarterScenario(allocator, path, "com.example.app", true);

    const content = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
    defer allocator.free(content);
    try std.testing.expect(std.mem.indexOf(u8, content, "\"appId\": \"com.example.app\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "\"action\": \"launch\"") != null);
}

test "app scaffold writes config smoke scenarios and gitignore without overwriting" {
    const allocator = std.testing.allocator;
    const dir = "zig-cache-test-app-scaffold";
    std.fs.cwd().deleteTree(dir) catch {};
    defer std.fs.cwd().deleteTree(dir) catch {};
    try std.fs.cwd().makePath(dir);

    try writeAppScaffold(allocator, dir, "com.example.mobiletest", false);

    const config_path = dir ++ "/.zmr/config.json";
    const android_path = dir ++ "/.zmr/android-smoke.json";
    const ios_path = dir ++ "/.zmr/ios-smoke.json";

    const config = try std.fs.cwd().readFileAlloc(allocator, config_path, 1024 * 1024);
    defer allocator.free(config);
    try std.testing.expect(std.mem.indexOf(u8, config, "\"schemaVersion\": 1") != null);
    try std.testing.expect(std.mem.indexOf(u8, config, "\"appId\": \"com.example.mobiletest\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, config, "\"doctor\": \"zmr doctor --strict --json --config .zmr/config.json\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, config, "\"pilotGate\": \"zmr-pilot-gate --android --ios --android-app-root . --ios-app-path ./build/Debug-iphonesimulator/Sample.app --runs 20 --min-pass-rate 100 --max-failures 0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, config, "\"serve\": \"zmr serve --transport stdio --device emulator-5554 --app-id com.example.mobiletest\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, config, "\"smokeScenario\": \".zmr/android-smoke.json\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, config, "\"smokeScenario\": \".zmr/ios-smoke.json\"") != null);

    const android = try std.fs.cwd().readFileAlloc(allocator, android_path, 1024 * 1024);
    defer allocator.free(android);
    try std.testing.expect(std.mem.indexOf(u8, android, "\"name\": \"Android smoke\"") != null);

    const ios = try std.fs.cwd().readFileAlloc(allocator, ios_path, 1024 * 1024);
    defer allocator.free(ios);
    try std.testing.expect(std.mem.indexOf(u8, ios, "\"name\": \"iOS smoke\"") != null);

    const gitignore = try std.fs.cwd().readFileAlloc(allocator, dir ++ "/.gitignore", 1024 * 1024);
    defer allocator.free(gitignore);
    try std.testing.expect(std.mem.indexOf(u8, gitignore, "traces/") != null);

    try std.testing.expectError(error.PathAlreadyExists, writeAppScaffold(allocator, dir, "com.example.other", false));
    try writeAppScaffold(allocator, dir, "com.example.other", true);

    const overwritten = try std.fs.cwd().readFileAlloc(allocator, config_path, 1024 * 1024);
    defer allocator.free(overwritten);
    try std.testing.expect(std.mem.indexOf(u8, overwritten, "\"appId\": \"com.example.other\"") != null);
}
