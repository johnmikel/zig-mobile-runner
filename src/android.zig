const std = @import("std");
const command = @import("command.zig");
const ios_shim = @import("ios_shim.zig");
const trace = @import("trace.zig");
const types = @import("types.zig");
const uiautomator = @import("uiautomator.zig");

const default_max_output = 32 * 1024 * 1024;
const default_adb_timeout_ms = 15_000;
const install_adb_timeout_ms = 120_000;
const shim_timeout_ms = 5_000;

pub const AndroidDevice = struct {
    allocator: std.mem.Allocator,
    adb_path: []const u8 = "adb",
    serial: ?[]const u8 = null,
    app_id: []const u8,
    shim_path: ?[]const u8 = null,

    pub fn init(
        allocator: std.mem.Allocator,
        adb_path: []const u8,
        serial: ?[]const u8,
        app_id: []const u8,
    ) !AndroidDevice {
        return try initWithShim(allocator, adb_path, serial, app_id, null);
    }

    pub fn initWithShim(
        allocator: std.mem.Allocator,
        adb_path: []const u8,
        serial: ?[]const u8,
        app_id: []const u8,
        shim_path: ?[]const u8,
    ) !AndroidDevice {
        return .{
            .allocator = allocator,
            .adb_path = try allocator.dupe(u8, adb_path),
            .serial = try types.dupeOptional(allocator, serial),
            .app_id = try allocator.dupe(u8, app_id),
            .shim_path = try types.dupeOptional(allocator, shim_path),
        };
    }

    pub fn deinit(self: *AndroidDevice) void {
        self.allocator.free(self.adb_path);
        if (self.serial) |value| self.allocator.free(value);
        self.allocator.free(self.app_id);
        if (self.shim_path) |value| self.allocator.free(value);
    }

    pub fn listDevices(self: *AndroidDevice) ![]types.DeviceInfo {
        return try listDevicesWithPath(self.allocator, self.adb_path);
    }

    pub fn install(self: *AndroidDevice, apk_path: []const u8) !void {
        const result = try self.runAdbWithTimeout(&.{ "install", "-r", apk_path }, default_max_output, install_adb_timeout_ms);
        defer result.deinit(self.allocator);
        try result.ensureSuccess();
    }

    pub fn launch(self: *AndroidDevice) !void {
        const result = try self.runAdb(&.{ "shell", "monkey", "-p", self.app_id, "-c", "android.intent.category.LAUNCHER", "1" }, default_max_output);
        defer result.deinit(self.allocator);
        try result.ensureSuccess();
    }

    pub fn stop(self: *AndroidDevice) !void {
        const result = try self.runAdb(&.{ "shell", "am", "force-stop", self.app_id }, default_max_output);
        defer result.deinit(self.allocator);
        try result.ensureSuccess();
    }

    pub fn clearState(self: *AndroidDevice) !void {
        const result = try self.runAdb(&.{ "shell", "pm", "clear", self.app_id }, default_max_output);
        defer result.deinit(self.allocator);
        try result.ensureSuccess();
    }

    pub fn openLink(self: *AndroidDevice, url: []const u8) !void {
        const result = try self.runAdb(&.{ "shell", "am", "start", "-W", "-a", "android.intent.action.VIEW", "-d", url, self.app_id }, default_max_output);
        defer result.deinit(self.allocator);
        try result.ensureSuccess();
    }

    pub fn tap(self: *AndroidDevice, x: i32, y: i32) !void {
        if (self.shim_path != null) return try self.runShimAction(.{ .kind = .tap, .x = x, .y = y });
        const sx = try std.fmt.allocPrint(self.allocator, "{d}", .{x});
        defer self.allocator.free(sx);
        const sy = try std.fmt.allocPrint(self.allocator, "{d}", .{y});
        defer self.allocator.free(sy);
        const result = try self.runAdb(&.{ "shell", "input", "tap", sx, sy }, default_max_output);
        defer result.deinit(self.allocator);
        try result.ensureSuccess();
    }

    pub fn typeText(self: *AndroidDevice, text: []const u8) !void {
        if (self.shim_path != null) return try self.runShimAction(.{ .kind = .type_text, .text = text });
        const escaped = try command.escapeAdbInputText(self.allocator, text);
        defer self.allocator.free(escaped);
        const result = try self.runAdb(&.{ "shell", "input", "text", escaped }, default_max_output);
        defer result.deinit(self.allocator);
        try result.ensureSuccess();
    }

    pub fn eraseText(self: *AndroidDevice, max_chars: u32) !void {
        if (self.shim_path != null) return try self.runShimAction(.{ .kind = .erase_text, .max_chars = max_chars });
        const script = try std.fmt.allocPrint(
            self.allocator,
            "input keyevent KEYCODE_MOVE_END; i=0; while [ $i -lt {d} ]; do input keyevent KEYCODE_DEL; i=$((i+1)); done",
            .{max_chars},
        );
        defer self.allocator.free(script);
        const result = try self.runAdb(&.{ "shell", "sh", "-c", script }, default_max_output);
        defer result.deinit(self.allocator);
        try result.ensureSuccess();
    }

    pub fn hideKeyboard(self: *AndroidDevice) !void {
        if (self.shim_path != null) return try self.runShimAction(.{ .kind = .hide_keyboard });
        const result = try self.runAdb(&.{ "shell", "input", "keyevent", "BACK" }, default_max_output);
        defer result.deinit(self.allocator);
        try result.ensureSuccess();
    }

    pub fn swipe(self: *AndroidDevice, x1: i32, y1: i32, x2: i32, y2: i32, duration_ms: u32) !void {
        if (self.shim_path != null) return try self.runShimAction(.{ .kind = .swipe, .x1 = x1, .y1 = y1, .x2 = x2, .y2 = y2, .duration_ms = duration_ms });
        const sx1 = try std.fmt.allocPrint(self.allocator, "{d}", .{x1});
        defer self.allocator.free(sx1);
        const sy1 = try std.fmt.allocPrint(self.allocator, "{d}", .{y1});
        defer self.allocator.free(sy1);
        const sx2 = try std.fmt.allocPrint(self.allocator, "{d}", .{x2});
        defer self.allocator.free(sx2);
        const sy2 = try std.fmt.allocPrint(self.allocator, "{d}", .{y2});
        defer self.allocator.free(sy2);
        const sd = try std.fmt.allocPrint(self.allocator, "{d}", .{duration_ms});
        defer self.allocator.free(sd);
        const result = try self.runAdb(&.{ "shell", "input", "swipe", sx1, sy1, sx2, sy2, sd }, default_max_output);
        defer result.deinit(self.allocator);
        try result.ensureSuccess();
    }

    pub fn pressBack(self: *AndroidDevice) !void {
        if (self.shim_path != null) return try self.runShimAction(.{ .kind = .press_back });
        const result = try self.runAdb(&.{ "shell", "input", "keyevent", "BACK" }, default_max_output);
        defer result.deinit(self.allocator);
        try result.ensureSuccess();
    }

    pub fn startScreenRecording(self: *AndroidDevice, remote_path: []const u8) !AndroidScreenRecording {
        const cleanup = self.runAdb(&.{ "shell", "rm", "-f", remote_path }, 4096) catch null;
        if (cleanup) |result| result.deinit(self.allocator);

        var argv = std.ArrayList([]const u8).empty;
        defer argv.deinit(self.allocator);
        try self.appendAdbBase(&argv);
        try argv.appendSlice(self.allocator, &.{ "shell", "screenrecord", remote_path });

        const owned_adb_path = try self.allocator.dupe(u8, self.adb_path);
        errdefer self.allocator.free(owned_adb_path);
        const owned_serial = try types.dupeOptional(self.allocator, self.serial);
        errdefer if (owned_serial) |value| self.allocator.free(value);
        const owned_remote_path = try self.allocator.dupe(u8, remote_path);
        errdefer self.allocator.free(owned_remote_path);

        var child = std.process.Child.init(argv.items, self.allocator);
        child.stdin_behavior = .Ignore;
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;
        try child.spawn();

        return .{
            .allocator = self.allocator,
            .adb_path = owned_adb_path,
            .serial = owned_serial,
            .remote_path = owned_remote_path,
            .child = child,
        };
    }

    pub fn settle(self: *AndroidDevice, timeout_ms: u64) !void {
        if (self.shim_path != null) {
            return try self.runShimAction(.{
                .kind = .settle,
                .duration_ms = @as(u32, @intCast(@min(timeout_ms, std.math.maxInt(u32)))),
            });
        }
        std.Thread.sleep(timeout_ms * std.time.ns_per_ms);
    }

    pub fn snapshot(self: *AndroidDevice, writer: ?*trace.TraceWriter) !types.ObservationSnapshot {
        const id = if (writer) |tw| try tw.nextSnapshotId() else try std.fmt.allocPrint(self.allocator, "snapshot-{d}", .{std.time.milliTimestamp()});
        errdefer self.allocator.free(id);

        const xml = if (self.shim_path == null) try self.dumpHierarchy() else null;
        defer if (xml) |value| self.allocator.free(value);
        const nodes = if (self.shim_path) |_|
            try self.snapshotNodesFromShim()
        else
            try uiautomator.parseHierarchy(self.allocator, xml.?);
        errdefer {
            for (nodes) |node| node.deinit(self.allocator);
            self.allocator.free(nodes);
        }

        var screenshot_artifact: ?[]const u8 = null;
        errdefer if (screenshot_artifact) |path| self.allocator.free(path);
        var tree_artifact: ?[]const u8 = null;
        errdefer if (tree_artifact) |path| self.allocator.free(path);

        if (writer) |tw| {
            if (tw.capture.capture_screenshots) {
                const screenshot = self.captureScreenshot() catch null;
                if (screenshot) |bytes| {
                    defer self.allocator.free(bytes);
                    const file_name = try std.fmt.allocPrint(self.allocator, "{s}.png", .{id});
                    defer self.allocator.free(file_name);
                    screenshot_artifact = try tw.writeArtifact(file_name, bytes);
                }
            }
            if (tw.capture.capture_hierarchy and xml != null) {
                const tree_name = try std.fmt.allocPrint(self.allocator, "{s}.xml", .{id});
                defer self.allocator.free(tree_name);
                tree_artifact = try tw.writeArtifact(tree_name, xml.?);
            }
        }

        const active = try self.activeWindow();
        errdefer active.deinit(self.allocator);

        const screen = self.viewport() catch types.Viewport{};
        const display_density_dpi = self.displayDensityDpi() catch null;
        const capture_logs = if (writer) |tw| tw.capture.capture_logs else true;
        const logs = if (capture_logs) self.logDelta() catch null else null;
        errdefer if (logs) |value| self.allocator.free(value);

        return .{
            .id = id,
            .timestamp_ms = std.time.milliTimestamp(),
            .viewport = screen,
            .display_density_dpi = display_density_dpi,
            .active_package = active.package,
            .active_activity = active.activity,
            .screenshot_artifact = screenshot_artifact,
            .tree_artifact = tree_artifact,
            .focused_node_id = null,
            .log_delta = logs,
            .nodes = nodes,
        };
    }

    fn dumpHierarchy(self: *AndroidDevice) ![]u8 {
        const result = try self.runAdb(&.{ "exec-out", "uiautomator", "dump", "/dev/tty" }, default_max_output);
        defer result.deinit(self.allocator);
        try result.ensureSuccess();
        return try self.allocator.dupe(u8, result.stdout);
    }

    fn captureScreenshot(self: *AndroidDevice) ![]u8 {
        const result = try self.runAdb(&.{ "exec-out", "screencap", "-p" }, default_max_output);
        defer result.deinit(self.allocator);
        try result.ensureSuccess();
        return try self.allocator.dupe(u8, result.stdout);
    }

    fn activeWindow(self: *AndroidDevice) !ActiveWindow {
        const result = try self.runAdb(&.{ "shell", "dumpsys", "window" }, default_max_output);
        defer result.deinit(self.allocator);
        try result.ensureSuccess();
        return try parseActiveWindow(self.allocator, result.stdout);
    }

    fn viewport(self: *AndroidDevice) !types.Viewport {
        const result = try self.runAdb(&.{ "shell", "wm", "size" }, 4096);
        defer result.deinit(self.allocator);
        try result.ensureSuccess();
        return parseViewport(result.stdout) catch types.Viewport{};
    }

    fn displayDensityDpi(self: *AndroidDevice) !?u32 {
        const result = try self.runAdb(&.{ "shell", "wm", "density" }, 4096);
        defer result.deinit(self.allocator);
        try result.ensureSuccess();
        return parseDisplayDensityDpi(result.stdout);
    }

    fn logDelta(self: *AndroidDevice) !?[]const u8 {
        const result = try self.runAdb(&.{ "logcat", "-d", "-t", "80" }, 1024 * 1024);
        defer result.deinit(self.allocator);
        if (result.term != .Exited or result.term.Exited != 0) return null;
        return try self.allocator.dupe(u8, result.stdout);
    }

    fn snapshotNodesFromShim(self: *AndroidDevice) ![]types.UiNode {
        const response = try self.runShim(.{ .kind = .snapshot });
        defer self.allocator.free(response);
        return try ios_shim.parseSnapshotNodes(self.allocator, response);
    }

    fn runShimAction(self: *AndroidDevice, shim_command: ios_shim.Command) !void {
        const response = try self.runShim(shim_command);
        defer self.allocator.free(response);
        try ios_shim.parseOkResponse(response);
    }

    fn runShim(self: *AndroidDevice, shim_command: ios_shim.Command) ![]u8 {
        const path = self.shim_path orelse return error.AndroidShimRequired;

        var input = std.ArrayList(u8).empty;
        defer input.deinit(self.allocator);
        try ios_shim.writeCommandJson(input.writer(self.allocator), shim_command);

        const result = try command.runWithInputTimeout(self.allocator, &.{path}, input.items, 4 * 1024 * 1024, shim_timeout_ms);
        defer result.deinit(self.allocator);
        try result.ensureSuccess();
        return try self.allocator.dupe(u8, result.stdout);
    }

    fn runAdb(self: *AndroidDevice, extra: []const []const u8, max_output_bytes: usize) !command.ExecResult {
        return try self.runAdbWithTimeout(extra, max_output_bytes, default_adb_timeout_ms);
    }

    fn runAdbWithTimeout(self: *AndroidDevice, extra: []const []const u8, max_output_bytes: usize, timeout_ms: u64) !command.ExecResult {
        var argv = std.ArrayList([]const u8).empty;
        defer argv.deinit(self.allocator);
        try self.appendAdbBase(&argv);
        try argv.appendSlice(self.allocator, extra);
        return try command.runWithTimeout(self.allocator, argv.items, max_output_bytes, timeout_ms);
    }

    fn appendAdbBase(self: *AndroidDevice, argv: *std.ArrayList([]const u8)) !void {
        try argv.append(self.allocator, self.adb_path);
        if (self.serial) |serial| {
            try argv.append(self.allocator, "-s");
            try argv.append(self.allocator, serial);
        }
    }
};

pub const AndroidScreenRecording = struct {
    allocator: std.mem.Allocator,
    adb_path: []const u8,
    serial: ?[]const u8,
    remote_path: []const u8,
    child: std.process.Child,
    stopped: bool = false,

    pub fn deinit(self: *AndroidScreenRecording) void {
        self.stopProcess() catch {};
        self.allocator.free(self.adb_path);
        if (self.serial) |value| self.allocator.free(value);
        self.allocator.free(self.remote_path);
    }

    pub fn stopAndPull(self: *AndroidScreenRecording, writer: *trace.TraceWriter, artifact_name: []const u8) ![]const u8 {
        try self.stopProcess();
        const artifact_path = try writer.artifactPath(artifact_name);
        errdefer self.allocator.free(artifact_path);

        const pull = try self.runAdb(&.{ "pull", self.remote_path, artifact_path }, default_max_output);
        defer pull.deinit(self.allocator);
        try pull.ensureSuccess();

        const cleanup = self.runAdb(&.{ "shell", "rm", "-f", self.remote_path }, 4096) catch null;
        if (cleanup) |result| result.deinit(self.allocator);

        return artifact_path;
    }

    fn stopProcess(self: *AndroidScreenRecording) !void {
        if (self.stopped) return;
        std.posix.kill(self.child.id, std.posix.SIG.INT) catch {};
        _ = try self.child.wait();
        self.stopped = true;
    }

    fn runAdb(self: *AndroidScreenRecording, extra: []const []const u8, max_output_bytes: usize) !command.ExecResult {
        var argv = std.ArrayList([]const u8).empty;
        defer argv.deinit(self.allocator);
        try argv.append(self.allocator, self.adb_path);
        if (self.serial) |serial| {
            try argv.append(self.allocator, "-s");
            try argv.append(self.allocator, serial);
        }
        try argv.appendSlice(self.allocator, extra);
        return try command.runWithTimeout(self.allocator, argv.items, max_output_bytes, default_adb_timeout_ms);
    }
};

pub fn listDevices(allocator: std.mem.Allocator, adb_path: []const u8) ![]types.DeviceInfo {
    return try listDevicesWithPath(allocator, adb_path);
}

fn listDevicesWithPath(allocator: std.mem.Allocator, adb_path: []const u8) ![]types.DeviceInfo {
    const result = try command.runWithTimeout(allocator, &.{ adb_path, "devices" }, 1024 * 1024, default_adb_timeout_ms);
    defer result.deinit(allocator);
    try result.ensureSuccess();

    var devices = std.ArrayList(types.DeviceInfo).empty;
    errdefer {
        for (devices.items) |device| device.deinit(allocator);
        devices.deinit(allocator);
    }

    var lines = std.mem.splitScalar(u8, result.stdout, '\n');
    _ = lines.next();
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r\n");
        if (line.len == 0) continue;
        var parts = std.mem.tokenizeAny(u8, line, " \t");
        const serial = parts.next() orelse continue;
        const state = parts.next() orelse continue;
        try devices.append(allocator, .{
            .serial = try allocator.dupe(u8, serial),
            .state = try allocator.dupe(u8, state),
        });
    }

    return try devices.toOwnedSlice(allocator);
}

pub const ActiveWindow = struct {
    package: ?[]const u8 = null,
    activity: ?[]const u8 = null,

    pub fn deinit(self: ActiveWindow, allocator: std.mem.Allocator) void {
        if (self.package) |value| allocator.free(value);
        if (self.activity) |value| allocator.free(value);
    }
};

pub fn parseActiveWindow(allocator: std.mem.Allocator, dumpsys: []const u8) !ActiveWindow {
    const markers = [_][]const u8{ "mCurrentFocus=", "mFocusedApp=", "topResumedActivity=" };
    for (markers) |marker| {
        if (std.mem.indexOf(u8, dumpsys, marker)) |pos| {
            const line_end = std.mem.indexOfScalarPos(u8, dumpsys, pos, '\n') orelse dumpsys.len;
            const line = dumpsys[pos..line_end];
            if (parsePackageActivity(allocator, line)) |active| return active else |_| continue;
        }
    }
    return .{};
}

fn parsePackageActivity(allocator: std.mem.Allocator, line: []const u8) !ActiveWindow {
    const slash = std.mem.indexOfScalar(u8, line, '/') orelse return error.NoActivity;
    var pkg_start = slash;
    while (pkg_start > 0) : (pkg_start -= 1) {
        const ch = line[pkg_start - 1];
        if (!(std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '.')) break;
    }
    var activity_end = slash + 1;
    while (activity_end < line.len) : (activity_end += 1) {
        const ch = line[activity_end];
        if (!(std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '.' or ch == '$')) break;
    }
    if (pkg_start >= slash or activity_end <= slash + 1) return error.NoActivity;
    return .{
        .package = try allocator.dupe(u8, line[pkg_start..slash]),
        .activity = try allocator.dupe(u8, line[slash + 1 .. activity_end]),
    };
}

pub fn parseViewport(output: []const u8) !types.Viewport {
    const marker = "Physical size:";
    const start = std.mem.indexOf(u8, output, marker) orelse return error.NoViewport;
    const after = std.mem.trim(u8, output[start + marker.len ..], " \t\r\n");
    const x = std.mem.indexOfScalar(u8, after, 'x') orelse return error.NoViewport;
    var end: usize = x + 1;
    while (end < after.len and std.ascii.isDigit(after[end])) : (end += 1) {}
    return .{
        .width = try std.fmt.parseInt(u32, std.mem.trim(u8, after[0..x], " \t"), 10),
        .height = try std.fmt.parseInt(u32, after[x + 1 .. end], 10),
    };
}

pub fn parseDisplayDensityDpi(output: []const u8) ?u32 {
    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r\n");
        const prefix = "Physical density:";
        if (!std.mem.startsWith(u8, line, prefix)) continue;
        const value = std.mem.trim(u8, line[prefix.len..], " \t\r\n");
        return std.fmt.parseInt(u32, value, 10) catch null;
    }
    return null;
}

test "parse active window package and activity" {
    const active = try parseActiveWindow(std.testing.allocator, "mCurrentFocus=Window{123 u0 com.example.mobiletest/.MainActivity}\n");
    defer active.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("com.example.mobiletest", active.package.?);
    try std.testing.expectEqualStrings(".MainActivity", active.activity.?);
}

test "parse viewport" {
    const viewport = try parseViewport("Physical size: 1080x2400\nOverride size: 1080x2200\n");
    try std.testing.expectEqual(@as(u32, 1080), viewport.width);
    try std.testing.expectEqual(@as(u32, 2400), viewport.height);
}

test "parse display density dpi" {
    try std.testing.expectEqual(@as(?u32, 420), parseDisplayDensityDpi("Physical density: 420\nOverride density: 440\n"));
    try std.testing.expectEqual(@as(?u32, null), parseDisplayDensityDpi("Override density: 440\n"));
}

test "android device actions and snapshot work through fake adb" {
    const allocator = std.testing.allocator;
    const dir = "zig-cache-test-android-trace";
    std.fs.cwd().deleteTree(dir) catch {};
    defer std.fs.cwd().deleteTree(dir) catch {};

    var device = try AndroidDevice.init(allocator, "./tests/fake-adb.sh", "fake-android-1", "com.example.mobiletest");
    defer device.deinit();

    try device.install("/tmp/app.apk");
    try device.launch();
    try device.stop();
    try device.clearState();
    try device.openLink("exampleapp://probe");
    try device.tap(10, 20);
    try device.typeText("hello world");
    try device.eraseText(3);
    try device.hideKeyboard();
    try device.swipe(1, 2, 3, 4, 5);
    try device.pressBack();

    var writer = try trace.TraceWriter.init(allocator, dir);
    defer writer.deinit();
    var snapshot = try device.snapshot(&writer);
    defer snapshot.deinit(allocator);
    try std.testing.expectEqualStrings("com.example.mobiletest", snapshot.active_package.?);
    try std.testing.expectEqualStrings(".MainActivity", snapshot.active_activity.?);
    try std.testing.expectEqual(@as(u32, 720), snapshot.viewport.width);
    try std.testing.expectEqual(@as(u32, 1280), snapshot.viewport.height);
    try std.testing.expectEqual(@as(?u32, 420), snapshot.display_density_dpi);
    try std.testing.expect(snapshot.screenshot_artifact != null);
    try std.testing.expect(snapshot.tree_artifact != null);
    try std.testing.expect(snapshot.log_delta != null);
    try std.testing.expect(snapshot.nodes.len > 0);

    const devices = try listDevices(allocator, "./tests/fake-adb.sh");
    defer {
        for (devices) |info| info.deinit(allocator);
        allocator.free(devices);
    }
    try std.testing.expectEqual(@as(usize, 1), devices.len);
    try std.testing.expectEqualStrings("fake-android-1", devices[0].serial);
    try std.testing.expectEqualStrings("device", devices[0].state);
}

test "android snapshot honors trace artifact capture controls" {
    const allocator = std.testing.allocator;
    const dir = "zig-cache/test-android-trace-capture-controls";
    std.fs.cwd().deleteTree(dir) catch {};
    defer std.fs.cwd().deleteTree(dir) catch {};

    var device = try AndroidDevice.init(allocator, "./tests/fake-adb.sh", "fake-android-1", "com.example.mobiletest");
    defer device.deinit();

    var writer = try trace.TraceWriter.initWithOptions(allocator, dir, .{
        .capture_screenshots = false,
        .capture_hierarchy = false,
        .capture_logs = false,
    });
    defer writer.deinit();

    var snapshot = try device.snapshot(&writer);
    defer snapshot.deinit(allocator);

    try std.testing.expect(snapshot.screenshot_artifact == null);
    try std.testing.expect(snapshot.tree_artifact == null);
    try std.testing.expect(snapshot.log_delta == null);
    try std.testing.expect(snapshot.nodes.len > 0);
}

test "android screen recording pulls mp4 into trace artifacts" {
    const allocator = std.testing.allocator;
    const dir = "zig-cache/test-android-screen-recording";
    std.fs.cwd().deleteTree(dir) catch {};
    defer std.fs.cwd().deleteTree(dir) catch {};

    var device = try AndroidDevice.init(allocator, "./tests/fake-adb.sh", "fake-android-1", "com.example.mobiletest");
    defer device.deinit();

    var writer = try trace.TraceWriter.init(allocator, dir);
    defer writer.deinit();

    var recording = try device.startScreenRecording("/sdcard/zmr-trace-screenrecord.mp4");
    defer recording.deinit();

    const artifact_path = try recording.stopAndPull(&writer, "screenrecord.mp4");
    defer allocator.free(artifact_path);

    const bytes = try std.fs.cwd().readFileAlloc(allocator, artifact_path, 1024);
    defer allocator.free(bytes);
    try std.testing.expectEqualStrings("FAKE_MP4\n", bytes);
}

test "android native shim supplies hierarchy and handles actions" {
    const allocator = std.testing.allocator;
    const dir = "zig-cache/test-android-native-shim";
    std.fs.cwd().deleteTree(dir) catch {};
    defer std.fs.cwd().deleteTree(dir) catch {};

    var device = try AndroidDevice.initWithShim(allocator, "./tests/fake-adb.sh", "fake-android-1", "com.example.mobiletest", "./tests/fake-android-shim.sh");
    defer device.deinit();

    var writer = try trace.TraceWriter.init(allocator, dir);
    defer writer.deinit();

    var snapshot = try device.snapshot(&writer);
    defer snapshot.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), snapshot.nodes.len);
    try std.testing.expectEqualStrings("Continue", snapshot.nodes[0].text.?);
    try std.testing.expectEqualStrings("continue_button", snapshot.nodes[0].resource_id.?);

    try device.tap(60, 42);
    try device.typeText("hello");
    try device.eraseText(5);
    try device.hideKeyboard();
    try device.swipe(1, 2, 3, 4, 5);
    try device.pressBack();
}
