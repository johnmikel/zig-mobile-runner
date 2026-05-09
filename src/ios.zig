const std = @import("std");
const command = @import("command.zig");
const ios_shim = @import("ios_shim.zig");
const selector = @import("selector.zig");
const trace = @import("trace.zig");
const types = @import("types.zig");

const default_max_output = 32 * 1024 * 1024;
const shim_timeout_ms = 180_000;
const simctl_retry_attempts = 6;
const simctl_retry_delay_ms = 500;

pub const TargetKind = enum {
    simulator,
    physical,
};

pub const IosDevice = struct {
    allocator: std.mem.Allocator,
    xcrun_path: []const u8 = "xcrun",
    udid: ?[]const u8 = null,
    app_id: []const u8,
    shim_path: ?[]const u8 = null,
    target_kind: TargetKind = .simulator,

    pub fn init(
        allocator: std.mem.Allocator,
        xcrun_path: []const u8,
        udid: ?[]const u8,
        app_id: []const u8,
    ) !IosDevice {
        return try initWithShim(allocator, xcrun_path, udid, app_id, null);
    }

    pub fn initWithShim(
        allocator: std.mem.Allocator,
        xcrun_path: []const u8,
        udid: ?[]const u8,
        app_id: []const u8,
        shim_path: ?[]const u8,
    ) !IosDevice {
        return try initWithKindAndShim(allocator, xcrun_path, udid, app_id, .simulator, shim_path);
    }

    pub fn initWithKindAndShim(
        allocator: std.mem.Allocator,
        xcrun_path: []const u8,
        udid: ?[]const u8,
        app_id: []const u8,
        target_kind: TargetKind,
        shim_path: ?[]const u8,
    ) !IosDevice {
        const owned_xcrun = try allocator.dupe(u8, xcrun_path);
        errdefer allocator.free(owned_xcrun);
        const owned_udid = try types.dupeOptional(allocator, udid);
        errdefer if (owned_udid) |value| allocator.free(value);
        const owned_app_id = try allocator.dupe(u8, app_id);
        errdefer allocator.free(owned_app_id);
        const owned_shim_path = try types.dupeOptional(allocator, shim_path);

        return .{
            .allocator = allocator,
            .xcrun_path = owned_xcrun,
            .udid = owned_udid,
            .app_id = owned_app_id,
            .shim_path = owned_shim_path,
            .target_kind = target_kind,
        };
    }

    pub fn deinit(self: *IosDevice) void {
        self.allocator.free(self.xcrun_path);
        if (self.udid) |value| self.allocator.free(value);
        self.allocator.free(self.app_id);
        if (self.shim_path) |value| self.allocator.free(value);
    }

    pub fn listDevices(self: *IosDevice) ![]types.DeviceInfo {
        return switch (self.target_kind) {
            .simulator => try listDevicesWithPath(self.allocator, self.xcrun_path),
            .physical => try listPhysicalDevicesWithPath(self.allocator, self.xcrun_path),
        };
    }

    pub fn install(self: *IosDevice, app_path: []const u8) !void {
        if (self.target_kind == .physical) return try self.installPhysical(app_path);
        const result = try self.runSimctl(&.{ "install", self.target(), app_path }, default_max_output);
        defer result.deinit(self.allocator);
        try result.ensureSuccess();
    }

    pub fn launch(self: *IosDevice) !void {
        if (self.target_kind == .physical) return try self.launchPhysical(null);
        const result = try self.runSimctl(&.{ "launch", self.target(), self.app_id }, default_max_output);
        defer result.deinit(self.allocator);
        try result.ensureSuccess();
    }

    pub fn stop(self: *IosDevice) !void {
        if (self.target_kind == .physical) return try self.stopPhysicalBestEffort();
        const result = try self.runSimctl(&.{ "terminate", self.target(), self.app_id }, default_max_output);
        defer result.deinit(self.allocator);
        try result.ensureSuccess();
    }

    pub fn clearState(self: *IosDevice) !void {
        if (self.target_kind == .physical) return try self.uninstallPhysicalBestEffort();
        const result = try self.runSimctl(&.{ "uninstall", self.target(), self.app_id }, default_max_output);
        defer result.deinit(self.allocator);
        if (isMissingInstalledApp(result)) return;
        try result.ensureSuccess();
    }

    pub fn openLink(self: *IosDevice, url: []const u8) !void {
        if (self.target_kind == .physical) return try self.launchPhysical(url);
        const result = try self.runSimctl(&.{ "openurl", self.target(), url }, default_max_output);
        defer result.deinit(self.allocator);
        try result.ensureSuccess();
    }

    pub fn tap(self: *IosDevice, x: i32, y: i32) !void {
        try self.runShimAction(.{ .kind = .tap, .x = x, .y = y });
    }

    pub fn tapBySelector(self: *IosDevice, wanted: selector.Selector) !bool {
        return try self.runShimSelectorAction(.{ .kind = .tap }, wanted);
    }

    pub fn typeText(self: *IosDevice, text: []const u8) !void {
        try self.runShimAction(.{ .kind = .type_text, .text = text });
    }

    pub fn typeTextBySelector(self: *IosDevice, wanted: selector.Selector, text: []const u8) !bool {
        return try self.runShimSelectorAction(.{ .kind = .type_text, .text = text }, wanted);
    }

    pub fn eraseText(self: *IosDevice, max_chars: u32) !void {
        try self.runShimAction(.{ .kind = .erase_text, .max_chars = max_chars });
    }

    pub fn eraseTextBySelector(self: *IosDevice, wanted: selector.Selector, max_chars: u32) !bool {
        return try self.runShimSelectorAction(.{ .kind = .erase_text, .max_chars = max_chars }, wanted);
    }

    pub fn hideKeyboard(self: *IosDevice) !void {
        try self.runShimAction(.{ .kind = .hide_keyboard });
    }

    pub fn swipe(self: *IosDevice, x1: i32, y1: i32, x2: i32, y2: i32, duration_ms: u32) !void {
        try self.runShimAction(.{ .kind = .swipe, .x1 = x1, .y1 = y1, .x2 = x2, .y2 = y2, .duration_ms = duration_ms });
    }

    pub fn pressBack(self: *IosDevice) !void {
        try self.runShimAction(.{ .kind = .press_back });
    }

    pub fn settle(self: *IosDevice, timeout_ms: u64) !void {
        if (self.shim_path != null) {
            return try self.runShimAction(.{
                .kind = .settle,
                .duration_ms = @as(u32, @intCast(@min(timeout_ms, std.math.maxInt(u32)))),
            });
        }
        std.Thread.sleep(timeout_ms * std.time.ns_per_ms);
    }

    pub fn snapshot(self: *IosDevice, writer: ?*trace.TraceWriter) !types.ObservationSnapshot {
        const id = if (writer) |tw| try tw.nextSnapshotId() else try std.fmt.allocPrint(self.allocator, "snapshot-{d}", .{std.time.milliTimestamp()});
        errdefer self.allocator.free(id);

        var screenshot_artifact: ?[]const u8 = null;
        errdefer if (screenshot_artifact) |path| self.allocator.free(path);
        var viewport: types.Viewport = .{};

        if (writer) |tw| {
            if (tw.capture.capture_screenshots) {
                const screenshot = self.captureScreenshot() catch null;
                if (screenshot) |bytes| {
                    defer self.allocator.free(bytes);
                    viewport = parsePngViewport(bytes) orelse .{};
                    const file_name = try std.fmt.allocPrint(self.allocator, "{s}.png", .{id});
                    defer self.allocator.free(file_name);
                    screenshot_artifact = try tw.writeArtifact(file_name, bytes);
                }
            }
        }

        const capture_logs = if (writer) |tw| tw.capture.capture_logs else true;
        const logs = if (capture_logs) self.logDelta() catch null else null;
        errdefer if (logs) |value| self.allocator.free(value);

        const active_package = try self.allocator.dupe(u8, self.app_id);
        errdefer self.allocator.free(active_package);
        const nodes = if (self.shim_path != null)
            try self.snapshotNodesFromShim()
        else
            try self.allocator.alloc(types.UiNode, 0);
        errdefer self.allocator.free(nodes);

        return .{
            .id = id,
            .timestamp_ms = std.time.milliTimestamp(),
            .viewport = viewport,
            .active_package = active_package,
            .active_activity = null,
            .screenshot_artifact = screenshot_artifact,
            .tree_artifact = null,
            .focused_node_id = null,
            .log_delta = logs,
            .nodes = nodes,
        };
    }

    fn captureScreenshot(self: *IosDevice) ![]u8 {
        if (self.target_kind == .physical) return error.IosPhysicalScreenshotUnsupported;
        const path = try std.fmt.allocPrint(self.allocator, "/tmp/zmr-ios-screenshot-{d}.png", .{std.time.nanoTimestamp()});
        defer self.allocator.free(path);
        defer std.fs.cwd().deleteFile(path) catch {};

        const result = try self.runSimctl(&.{ "io", self.target(), "screenshot", path }, default_max_output);
        defer result.deinit(self.allocator);
        try result.ensureSuccess();
        return try std.fs.cwd().readFileAlloc(self.allocator, path, default_max_output);
    }

    fn logDelta(self: *IosDevice) !?[]const u8 {
        if (self.target_kind == .physical) return null;
        const result = try self.runSimctl(&.{ "spawn", self.target(), "log", "show", "--style", "compact", "--last", "30s" }, 1024 * 1024);
        defer result.deinit(self.allocator);
        if (result.term != .Exited or result.term.Exited != 0) return null;
        return try self.allocator.dupe(u8, result.stdout);
    }

    fn snapshotNodesFromShim(self: *IosDevice) ![]types.UiNode {
        const response = try self.runShim(.{ .kind = .snapshot });
        defer self.allocator.free(response);
        return try ios_shim.parseSnapshotNodes(self.allocator, response);
    }

    fn runShimAction(self: *IosDevice, shim_command: ios_shim.Command) !void {
        const response = try self.runShim(shim_command);
        defer self.allocator.free(response);
        try ios_shim.parseOkResponse(response);
    }

    fn runShimSelectorAction(self: *IosDevice, shim_command: ios_shim.Command, wanted: selector.Selector) !bool {
        if (self.shim_path == null) return false;
        const shim_selector = try ios_shim.selectorString(self.allocator, wanted) orelse return false;
        defer self.allocator.free(shim_selector);

        var command_with_selector = shim_command;
        command_with_selector.selector = shim_selector;
        try self.runShimAction(command_with_selector);
        return true;
    }

    fn runShim(self: *IosDevice, shim_command: ios_shim.Command) ![]u8 {
        const path = self.shim_path orelse return error.IosXCTestShimRequired;

        var input = std.ArrayList(u8).empty;
        defer input.deinit(self.allocator);
        try ios_shim.writeCommandJson(input.writer(self.allocator), shim_command);

        const result = try command.runWithInputTimeout(self.allocator, &.{path}, input.items, 4 * 1024 * 1024, shim_timeout_ms);
        defer result.deinit(self.allocator);
        try result.ensureSuccess();
        return try self.allocator.dupe(u8, result.stdout);
    }

    fn target(self: *IosDevice) []const u8 {
        return self.udid orelse "booted";
    }

    fn runSimctl(self: *IosDevice, extra: []const []const u8, max_output_bytes: usize) !command.ExecResult {
        return try runSimctlCommand(self.allocator, self.xcrun_path, extra, max_output_bytes);
    }

    fn installPhysical(self: *IosDevice, app_path: []const u8) !void {
        const result = try self.runDevicectl(&.{ "device", "install", "app", "--device", self.target(), app_path }, default_max_output);
        defer result.deinit(self.allocator);
        try result.ensureSuccess();
    }

    fn launchPhysical(self: *IosDevice, url: ?[]const u8) !void {
        var argv = std.ArrayList([]const u8).empty;
        defer argv.deinit(self.allocator);
        try argv.appendSlice(self.allocator, &.{ "device", "process", "launch", "--device", self.target(), "--terminate-existing" });
        if (url) |value| try argv.appendSlice(self.allocator, &.{ "--payload-url", value });
        try argv.append(self.allocator, self.app_id);

        const result = try self.runDevicectl(argv.items, default_max_output);
        defer result.deinit(self.allocator);
        try result.ensureSuccess();
    }

    fn stopPhysicalBestEffort(self: *IosDevice) !void {
        const process_json = self.runDevicectlJson(&.{ "device", "info", "processes", "--device", self.target() }) catch return;
        defer self.allocator.free(process_json);
        const pid = findPidForBundleId(self.allocator, process_json, self.app_id) catch null;
        if (pid) |value| {
            const pid_text = try std.fmt.allocPrint(self.allocator, "{d}", .{value});
            defer self.allocator.free(pid_text);
            const result = try self.runDevicectl(&.{ "device", "process", "terminate", "--device", self.target(), "--pid", pid_text }, default_max_output);
            defer result.deinit(self.allocator);
            try result.ensureSuccess();
        }
    }

    fn uninstallPhysicalBestEffort(self: *IosDevice) !void {
        const result = try self.runDevicectl(&.{ "device", "uninstall", "app", "--device", self.target(), self.app_id }, default_max_output);
        defer result.deinit(self.allocator);
        if (isMissingInstalledApp(result)) return;
        try result.ensureSuccess();
    }

    fn runDevicectl(self: *IosDevice, extra: []const []const u8, max_output_bytes: usize) !command.ExecResult {
        return try runDevicectlCommand(self.allocator, self.xcrun_path, extra, max_output_bytes);
    }

    fn runDevicectlJson(self: *IosDevice, extra: []const []const u8) ![]u8 {
        return try runDevicectlJsonCommand(self.allocator, self.xcrun_path, extra);
    }
};

fn parsePngViewport(bytes: []const u8) ?types.Viewport {
    const signature = "\x89PNG\r\n\x1a\n";
    if (bytes.len < 24 or !std.mem.eql(u8, bytes[0..8], signature)) return null;
    if (!std.mem.eql(u8, bytes[12..16], "IHDR")) return null;

    return .{
        .width = readBigEndianU32(bytes[16..20]),
        .height = readBigEndianU32(bytes[20..24]),
    };
}

fn readBigEndianU32(bytes: []const u8) u32 {
    return (@as(u32, bytes[0]) << 24) |
        (@as(u32, bytes[1]) << 16) |
        (@as(u32, bytes[2]) << 8) |
        @as(u32, bytes[3]);
}

pub fn listDevices(allocator: std.mem.Allocator, xcrun_path: []const u8) ![]types.DeviceInfo {
    return try listDevicesWithPath(allocator, xcrun_path);
}

pub fn listPhysicalDevices(allocator: std.mem.Allocator, xcrun_path: []const u8) ![]types.DeviceInfo {
    return try listPhysicalDevicesWithPath(allocator, xcrun_path);
}

fn listDevicesWithPath(allocator: std.mem.Allocator, xcrun_path: []const u8) ![]types.DeviceInfo {
    const result = try runSimctlCommand(allocator, xcrun_path, &.{ "list", "devices", "--json" }, 4 * 1024 * 1024);
    defer result.deinit(allocator);
    try result.ensureSuccess();
    return try parseDevicesJson(allocator, result.stdout);
}

fn runSimctlCommand(
    allocator: std.mem.Allocator,
    xcrun_path: []const u8,
    extra: []const []const u8,
    max_output_bytes: usize,
) !command.ExecResult {
    var argv = std.ArrayList([]const u8).empty;
    defer argv.deinit(allocator);
    try argv.append(allocator, xcrun_path);
    try argv.append(allocator, "simctl");
    try argv.appendSlice(allocator, extra);

    var attempt: usize = 0;
    while (true) {
        const result = try command.run(allocator, argv.items, max_output_bytes);
        if (attempt + 1 >= simctl_retry_attempts or !isRetriableSimctlFailure(result)) {
            return result;
        }
        result.deinit(allocator);
        attempt += 1;
        std.Thread.sleep(simctl_retry_delay_ms * std.time.ns_per_ms);
    }
}

fn runDevicectlCommand(
    allocator: std.mem.Allocator,
    xcrun_path: []const u8,
    extra: []const []const u8,
    max_output_bytes: usize,
) !command.ExecResult {
    var argv = std.ArrayList([]const u8).empty;
    defer argv.deinit(allocator);
    try argv.append(allocator, xcrun_path);
    try argv.append(allocator, "devicectl");
    try argv.appendSlice(allocator, extra);
    return try command.run(allocator, argv.items, max_output_bytes);
}

fn runDevicectlJsonCommand(
    allocator: std.mem.Allocator,
    xcrun_path: []const u8,
    extra: []const []const u8,
) ![]u8 {
    const path = try std.fmt.allocPrint(allocator, "/tmp/zmr-devicectl-{d}.json", .{std.time.nanoTimestamp()});
    defer allocator.free(path);
    defer std.fs.cwd().deleteFile(path) catch {};

    var argv = std.ArrayList([]const u8).empty;
    defer argv.deinit(allocator);
    try argv.append(allocator, xcrun_path);
    try argv.append(allocator, "devicectl");
    try argv.appendSlice(allocator, extra);
    try argv.appendSlice(allocator, &.{ "--json-output", path, "--quiet" });

    const result = try command.run(allocator, argv.items, default_max_output);
    defer result.deinit(allocator);
    try result.ensureSuccess();
    return try std.fs.cwd().readFileAlloc(allocator, path, default_max_output);
}

fn listPhysicalDevicesWithPath(allocator: std.mem.Allocator, xcrun_path: []const u8) ![]types.DeviceInfo {
    const json = try runDevicectlJsonCommand(allocator, xcrun_path, &.{ "list", "devices" });
    defer allocator.free(json);
    return try parsePhysicalDevicesJson(allocator, json);
}

fn isRetriableSimctlFailure(result: command.ExecResult) bool {
    if (result.timed_out) return false;
    switch (result.term) {
        .Exited => |code| if (code == 0) return false,
        else => return false,
    }
    return std.mem.indexOf(u8, result.stderr, "CoreSimulatorService connection became invalid") != null or
        std.mem.indexOf(u8, result.stderr, "Failed to initialize simulator device set") != null or
        std.mem.indexOf(u8, result.stderr, "simdiskimaged") != null or
        std.mem.indexOf(u8, result.stderr, "Connection refused") != null;
}

pub fn parseDevicesJson(allocator: std.mem.Allocator, content: []const u8) ![]types.DeviceInfo {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, content, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.SimctlDevicesMustBeObject;
    const devices_value = parsed.value.object.get("devices") orelse return error.SimctlDevicesMissingDevices;
    if (devices_value != .object) return error.SimctlDevicesMustBeObject;

    var devices = std.ArrayList(types.DeviceInfo).empty;
    errdefer {
        for (devices.items) |device| device.deinit(allocator);
        devices.deinit(allocator);
    }

    var runtime_iterator = devices_value.object.iterator();
    while (runtime_iterator.next()) |runtime_entry| {
        const runtime_devices = runtime_entry.value_ptr.*;
        if (runtime_devices != .array) continue;
        for (runtime_devices.array.items) |device_value| {
            if (device_value != .object) continue;
            const object = device_value.object;
            if (fieldBool(object, "isAvailable") == false) continue;
            const udid = fieldString(object, "udid") orelse continue;
            const state = fieldString(object, "state") orelse continue;
            if (!std.mem.eql(u8, state, "Booted")) continue;
            try devices.append(allocator, .{
                .serial = try allocator.dupe(u8, udid),
                .state = try allocator.dupe(u8, state),
            });
        }
    }

    return try devices.toOwnedSlice(allocator);
}

pub fn parsePhysicalDevicesJson(allocator: std.mem.Allocator, content: []const u8) ![]types.DeviceInfo {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, content, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.DevicectlDevicesMustBeObject;
    const result_value = parsed.value.object.get("result") orelse return error.DevicectlDevicesMissingResult;
    if (result_value != .object) return error.DevicectlDevicesMustBeObject;
    const devices_value = result_value.object.get("devices") orelse return error.DevicectlDevicesMissingDevices;
    if (devices_value != .array) return error.DevicectlDevicesMustBeArray;

    var devices = std.ArrayList(types.DeviceInfo).empty;
    errdefer {
        for (devices.items) |device| device.deinit(allocator);
        devices.deinit(allocator);
    }

    for (devices_value.array.items) |device_value| {
        if (device_value != .object) continue;
        const object = device_value.object;
        const hardware = fieldObject(object, "hardwareProperties") orelse continue;
        if (!fieldStringEquals(hardware, "platform", "iOS")) continue;
        if (!fieldStringEquals(hardware, "reality", "physical")) continue;
        const serial = fieldString(hardware, "udid") orelse fieldString(object, "identifier") orelse continue;
        const connection = fieldObject(object, "connectionProperties");
        const state = if (connection) |value|
            fieldString(value, "tunnelState") orelse fieldString(value, "pairingState") orelse "available"
        else
            "available";
        try devices.append(allocator, .{
            .serial = try allocator.dupe(u8, serial),
            .state = try allocator.dupe(u8, state),
        });
    }

    return try devices.toOwnedSlice(allocator);
}

fn fieldObject(object: std.json.ObjectMap, key: []const u8) ?std.json.ObjectMap {
    const value = object.get(key) orelse return null;
    if (value != .object) return null;
    return value.object;
}

fn fieldStringEquals(object: std.json.ObjectMap, key: []const u8, expected: []const u8) bool {
    const value = fieldString(object, key) orelse return false;
    return std.mem.eql(u8, value, expected);
}

fn findPidForBundleId(allocator: std.mem.Allocator, content: []const u8, app_id: []const u8) !?i64 {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, content, .{});
    defer parsed.deinit();
    return findPidInValue(parsed.value, app_id);
}

fn findPidInValue(value: std.json.Value, app_id: []const u8) ?i64 {
    switch (value) {
        .object => |object| {
            var has_bundle = false;
            var pid: ?i64 = null;
            var iterator = object.iterator();
            while (iterator.next()) |entry| {
                if (entry.value_ptr.* == .string and std.mem.eql(u8, entry.value_ptr.string, app_id)) {
                    has_bundle = true;
                }
                if (std.mem.indexOf(u8, entry.key_ptr.*, "pid") != null or std.mem.indexOf(u8, entry.key_ptr.*, "processIdentifier") != null) {
                    if (entry.value_ptr.* == .integer) pid = entry.value_ptr.integer;
                }
                if (findPidInValue(entry.value_ptr.*, app_id)) |nested| return nested;
            }
            if (has_bundle) return pid;
            return null;
        },
        .array => |array| {
            for (array.items) |item| {
                if (findPidInValue(item, app_id)) |pid| return pid;
            }
            return null;
        },
        else => return null,
    }
}

fn fieldString(object: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const value = object.get(key) orelse return null;
    if (value != .string) return null;
    return value.string;
}

fn fieldBool(object: std.json.ObjectMap, key: []const u8) bool {
    const value = object.get(key) orelse return true;
    if (value != .bool) return true;
    return value.bool;
}

fn isMissingInstalledApp(result: command.ExecResult) bool {
    switch (result.term) {
        .Exited => |code| if (code == 0) return false,
        else => return false,
    }
    return std.mem.indexOf(u8, result.stderr, "No installed application with bundle identifier") != null;
}

test "ios simulator adapter lists devices and supports lifecycle snapshot smoke" {
    const allocator = std.testing.allocator;
    const dir = "zig-cache-test-ios-trace";
    std.fs.cwd().deleteTree(dir) catch {};
    defer std.fs.cwd().deleteTree(dir) catch {};

    const devices = try listDevices(allocator, "./tests/fake-xcrun.sh");
    defer {
        for (devices) |device| device.deinit(allocator);
        allocator.free(devices);
    }
    try std.testing.expectEqual(@as(usize, 1), devices.len);
    try std.testing.expectEqualStrings("fake-ios-1", devices[0].serial);
    try std.testing.expectEqualStrings("Booted", devices[0].state);

    var device = try IosDevice.init(allocator, "./tests/fake-xcrun.sh", "fake-ios-1", "com.example.mobiletest");
    defer device.deinit();

    try device.install("/tmp/Sample.app");
    try device.launch();
    try device.openLink("exampleapp:///e2e-auth?probe=1");
    try device.stop();
    try device.clearState();

    var writer = try trace.TraceWriter.init(allocator, dir);
    defer writer.deinit();
    var snapshot = try device.snapshot(&writer);
    defer snapshot.deinit(allocator);

    try std.testing.expectEqualStrings("com.example.mobiletest", snapshot.active_package.?);
    try std.testing.expect(snapshot.screenshot_artifact != null);
    try std.testing.expectEqual(@as(u32, 2), snapshot.viewport.width);
    try std.testing.expectEqual(@as(u32, 3), snapshot.viewport.height);
    try std.testing.expect(snapshot.log_delta != null);
    try std.testing.expectEqual(@as(usize, 0), snapshot.nodes.len);
}

test "ios snapshot honors trace artifact capture controls" {
    const allocator = std.testing.allocator;
    const dir = "zig-cache/test-ios-trace-capture-controls";
    std.fs.cwd().deleteTree(dir) catch {};
    defer std.fs.cwd().deleteTree(dir) catch {};

    var device = try IosDevice.init(allocator, "./tests/fake-xcrun.sh", "fake-ios-1", "com.example.mobiletest");
    defer device.deinit();

    var writer = try trace.TraceWriter.initWithOptions(allocator, dir, .{
        .capture_screenshots = false,
        .capture_hierarchy = false,
        .capture_logs = false,
    });
    defer writer.deinit();

    var snapshot = try device.snapshot(&writer);
    defer snapshot.deinit(allocator);

    try std.testing.expectEqualStrings("com.example.mobiletest", snapshot.active_package.?);
    try std.testing.expect(snapshot.screenshot_artifact == null);
    try std.testing.expect(snapshot.log_delta == null);
    try std.testing.expectEqual(@as(usize, 0), snapshot.nodes.len);
}

test "ios clear state treats an already uninstalled app as clean" {
    const allocator = std.testing.allocator;
    var device = try IosDevice.init(allocator, "./tests/fake-xcrun-missing-ios-app.sh", "fake-ios-1", "com.example.mobiletest");
    defer device.deinit();

    try device.clearState();
}

test "ios simctl parser filters unavailable and shutdown devices" {
    const allocator = std.testing.allocator;
    const devices = try parseDevicesJson(allocator,
        \\{
        \\  "devices": {
        \\    "com.apple.CoreSimulator.SimRuntime.iOS-18-5": [
        \\      {"name":"iPhone 16","udid":"booted-1","state":"Booted","isAvailable":true},
        \\      {"name":"iPhone 15","udid":"shutdown-1","state":"Shutdown","isAvailable":true},
        \\      {"name":"iPhone 14","udid":"gone-1","state":"Booted","isAvailable":false}
        \\    ]
        \\  }
        \\}
    );
    defer {
        for (devices) |device| device.deinit(allocator);
        allocator.free(devices);
    }

    try std.testing.expectEqual(@as(usize, 1), devices.len);
    try std.testing.expectEqualStrings("booted-1", devices[0].serial);
    try std.testing.expectEqualStrings("Booted", devices[0].state);
}

test "ios device listing retries transient CoreSimulator failures" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var script = try tmp.dir.createFile("fake-xcrun-flaky.sh", .{ .truncate = true });
    try script.writeAll(
        \\#!/usr/bin/env bash
        \\set -euo pipefail
        \\
        \\state="$(dirname "$0")/state"
        \\if [[ "${1:-}" == "--version" ]]; then
        \\  printf 'xcrun version 70\n'
        \\  exit 0
        \\fi
        \\if [[ "${1:-}" != "simctl" ]]; then
        \\  echo "expected simctl command: $*" >&2
        \\  exit 2
        \\fi
        \\shift
        \\if [[ ! -e "$state" ]]; then
        \\  touch "$state"
        \\  echo "CoreSimulatorService connection became invalid" >&2
        \\  echo "Failed to initialize simulator device set" >&2
        \\  exit 61
        \\fi
        \\if [[ "${1:-}" == "list" && "${2:-}" == "devices" && "${3:-}" == "--json" ]]; then
        \\  cat <<'JSON'
        \\{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-5":[{"name":"iPhone","udid":"retry-ios-1","state":"Booted","isAvailable":true}]}}
        \\JSON
        \\  exit 0
        \\fi
        \\echo "unsupported simctl command: $*" >&2
        \\exit 2
        \\
    );
    try script.chmod(0o755);
    script.close();

    const script_path = try std.fmt.allocPrint(allocator, ".zig-cache/tmp/{s}/fake-xcrun-flaky.sh", .{tmp.sub_path});
    defer allocator.free(script_path);

    const devices = try listDevices(allocator, script_path);
    defer {
        for (devices) |device| device.deinit(allocator);
        allocator.free(devices);
    }

    try std.testing.expectEqual(@as(usize, 1), devices.len);
    try std.testing.expectEqualStrings("retry-ios-1", devices[0].serial);
}

test "ios physical device adapter lists devices and supports devicectl lifecycle" {
    const allocator = std.testing.allocator;

    const devices = try listPhysicalDevices(allocator, "./tests/fake-xcrun.sh");
    defer {
        for (devices) |device| device.deinit(allocator);
        allocator.free(devices);
    }
    try std.testing.expectEqual(@as(usize, 1), devices.len);
    try std.testing.expectEqualStrings("fake-physical-ios-1", devices[0].serial);
    try std.testing.expectEqualStrings("connected", devices[0].state);

    var device = try IosDevice.initWithKindAndShim(allocator, "./tests/fake-xcrun.sh", "fake-physical-ios-1", "com.example.mobiletest", .physical, null);
    defer device.deinit();

    try device.install("/tmp/Sample.app");
    try device.launch();
    try device.openLink("exampleapp:///e2e-auth?probe=1");
    try device.stop();
    try device.clearState();

    var snapshot = try device.snapshot(null);
    defer snapshot.deinit(allocator);
    try std.testing.expectEqualStrings("com.example.mobiletest", snapshot.active_package.?);
    try std.testing.expect(snapshot.screenshot_artifact == null);
    try std.testing.expect(snapshot.log_delta == null);
}

test "ios physical devicectl parser filters iOS physical devices" {
    const allocator = std.testing.allocator;
    const devices = try parsePhysicalDevicesJson(allocator,
        \\{
        \\  "result": {
        \\    "devices": [
        \\      {
        \\        "identifier": "coredevice-1",
        \\        "connectionProperties": {"pairingState": "paired", "tunnelState": "connected"},
        \\        "hardwareProperties": {"platform": "iOS", "reality": "physical", "udid": "physical-1"}
        \\      },
        \\      {
        \\        "identifier": "sim-1",
        \\        "connectionProperties": {"pairingState": "paired"},
        \\        "hardwareProperties": {"platform": "iOS", "reality": "virtual", "udid": "sim-1"}
        \\      },
        \\      {
        \\        "identifier": "watch-1",
        \\        "connectionProperties": {"pairingState": "paired"},
        \\        "hardwareProperties": {"platform": "watchOS", "udid": "watch-1"}
        \\      }
        \\    ]
        \\  }
        \\}
    );
    defer {
        for (devices) |device| device.deinit(allocator);
        allocator.free(devices);
    }

    try std.testing.expectEqual(@as(usize, 1), devices.len);
    try std.testing.expectEqualStrings("physical-1", devices[0].serial);
    try std.testing.expectEqualStrings("connected", devices[0].state);
}

test "ios selector-grade interactions require XCTest shim" {
    const allocator = std.testing.allocator;
    var device = try IosDevice.init(allocator, "./tests/fake-xcrun.sh", "fake-ios-1", "com.example.mobiletest");
    defer device.deinit();

    try std.testing.expectError(error.IosXCTestShimRequired, device.tap(1, 2));
    try std.testing.expectError(error.IosXCTestShimRequired, device.typeText("hello"));
    try std.testing.expectError(error.IosXCTestShimRequired, device.eraseText(3));
    try std.testing.expectError(error.IosXCTestShimRequired, device.hideKeyboard());
    try std.testing.expectError(error.IosXCTestShimRequired, device.swipe(1, 2, 3, 4, 5));
    try std.testing.expectError(error.IosXCTestShimRequired, device.pressBack());
}

test "ios xctest shim timeout allows cold xcodebuild startup" {
    try std.testing.expect(shim_timeout_ms >= 120_000);
}

test "ios xctest shim supplies hierarchy and handles selector actions" {
    const allocator = std.testing.allocator;
    const dir = "zig-cache/test-ios-xctest-shim";
    std.fs.cwd().deleteTree(dir) catch {};
    defer std.fs.cwd().deleteTree(dir) catch {};

    var device = try IosDevice.initWithShim(allocator, "./tests/fake-xcrun.sh", "fake-ios-1", "com.example.mobiletest", "./tests/fake-ios-shim.sh");
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
    try std.testing.expect(try device.tapBySelector(.{ .text = "Continue" }));
    try std.testing.expect(try device.typeTextBySelector(.{ .id = "continue_button" }, "hello"));
    try std.testing.expect(try device.eraseTextBySelector(.{ .content_desc_contains = "continue" }, 5));
    try std.testing.expect(!try device.tapBySelector(.{ .text = "Continue", .id = "continue_button" }));
    try device.hideKeyboard();
    try device.swipe(1, 2, 3, 4, 5);
    try device.pressBack();
}
