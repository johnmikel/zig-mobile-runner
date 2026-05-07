const std = @import("std");
const types = @import("types.zig");

pub const FakeDevice = struct {
    allocator: std.mem.Allocator,
    snapshots: []types.ObservationSnapshot,
    snapshot_index: usize = 0,
    taps: usize = 0,
    swipes: usize = 0,
    erases: usize = 0,
    hides_keyboard: usize = 0,
    presses_back: usize = 0,
    stopped: bool = false,
    cleared: bool = false,
    last_swipe: ?SwipeRecord = null,
    last_erase_chars: u32 = 0,
    typed_text: std.ArrayList([]const u8),
    launched: bool = false,
    installed_path: ?[]const u8 = null,
    opened_link: ?[]const u8 = null,
    settles: usize = 0,
    last_settle_timeout_ms: u64 = 0,

    pub fn init(allocator: std.mem.Allocator, snapshots: []types.ObservationSnapshot) FakeDevice {
        return .{
            .allocator = allocator,
            .snapshots = snapshots,
            .typed_text = std.ArrayList([]const u8).empty,
        };
    }

    pub fn deinit(self: *FakeDevice) void {
        for (self.typed_text.items) |text| self.allocator.free(text);
        self.typed_text.deinit(self.allocator);
        if (self.installed_path) |value| self.allocator.free(value);
        if (self.opened_link) |value| self.allocator.free(value);
    }

    pub fn install(self: *FakeDevice, apk_path: []const u8) !void {
        if (self.installed_path) |value| self.allocator.free(value);
        self.installed_path = try self.allocator.dupe(u8, apk_path);
    }

    pub fn launch(self: *FakeDevice) !void {
        self.launched = true;
    }

    pub fn stop(self: *FakeDevice) !void {
        self.stopped = true;
    }

    pub fn clearState(self: *FakeDevice) !void {
        self.cleared = true;
    }

    pub fn listDevices(self: *FakeDevice) ![]types.DeviceInfo {
        const devices = try self.allocator.alloc(types.DeviceInfo, 1);
        errdefer self.allocator.free(devices);
        const serial = try self.allocator.dupe(u8, "fake-device-1");
        errdefer self.allocator.free(serial);
        const state = try self.allocator.dupe(u8, "device");
        devices[0] = .{
            .serial = serial,
            .state = state,
        };
        return devices;
    }

    pub fn openLink(self: *FakeDevice, url: []const u8) !void {
        if (self.opened_link) |value| self.allocator.free(value);
        self.opened_link = try self.allocator.dupe(u8, url);
    }

    pub fn tap(self: *FakeDevice, x: i32, y: i32) !void {
        _ = x;
        _ = y;
        self.taps += 1;
    }

    pub fn typeText(self: *FakeDevice, text: []const u8) !void {
        try self.typed_text.append(self.allocator, try self.allocator.dupe(u8, text));
    }

    pub fn eraseText(self: *FakeDevice, max_chars: u32) !void {
        self.last_erase_chars = max_chars;
        self.erases += 1;
    }

    pub fn hideKeyboard(self: *FakeDevice) !void {
        self.hides_keyboard += 1;
    }

    pub fn swipe(self: *FakeDevice, x1: i32, y1: i32, x2: i32, y2: i32, duration_ms: u32) !void {
        self.swipes += 1;
        self.last_swipe = .{
            .x1 = x1,
            .y1 = y1,
            .x2 = x2,
            .y2 = y2,
            .duration_ms = duration_ms,
        };
    }

    pub fn pressBack(self: *FakeDevice) !void {
        self.presses_back += 1;
    }

    pub fn settle(self: *FakeDevice, timeout_ms: u64) !void {
        self.settles += 1;
        self.last_settle_timeout_ms = timeout_ms;
    }

    pub fn snapshot(self: *FakeDevice, writer: anytype) !types.ObservationSnapshot {
        _ = writer;
        if (self.snapshots.len == 0) return error.NoFakeSnapshots;
        const index = @min(self.snapshot_index, self.snapshots.len - 1);
        if (self.snapshot_index + 1 < self.snapshots.len) self.snapshot_index += 1;
        return try cloneSnapshot(self.allocator, self.snapshots[index]);
    }
};

pub const SwipeRecord = struct {
    x1: i32,
    y1: i32,
    x2: i32,
    y2: i32,
    duration_ms: u32,
};

pub fn cloneSnapshot(allocator: std.mem.Allocator, source: types.ObservationSnapshot) !types.ObservationSnapshot {
    var nodes = try allocator.alloc(types.UiNode, source.nodes.len);
    errdefer allocator.free(nodes);
    var initialized: usize = 0;
    errdefer {
        for (nodes[0..initialized]) |node| node.deinit(allocator);
    }
    for (source.nodes, 0..) |node, index| {
        nodes[index] = .{
            .stable_id = try allocator.dupe(u8, node.stable_id),
            .class_name = try allocator.dupe(u8, node.class_name),
            .resource_id = try types.dupeOptional(allocator, node.resource_id),
            .text = try types.dupeOptional(allocator, node.text),
            .content_desc = try types.dupeOptional(allocator, node.content_desc),
            .bounds = node.bounds,
            .enabled = node.enabled,
            .visible = node.visible,
            .selected = node.selected,
        };
        initialized += 1;
    }
    return .{
        .id = try allocator.dupe(u8, source.id),
        .timestamp_ms = source.timestamp_ms,
        .viewport = source.viewport,
        .active_package = try types.dupeOptional(allocator, source.active_package),
        .active_activity = try types.dupeOptional(allocator, source.active_activity),
        .screenshot_artifact = try types.dupeOptional(allocator, source.screenshot_artifact),
        .tree_artifact = try types.dupeOptional(allocator, source.tree_artifact),
        .focused_node_id = try types.dupeOptional(allocator, source.focused_node_id),
        .log_delta = try types.dupeOptional(allocator, source.log_delta),
        .nodes = nodes,
    };
}

test "fake device records commands and replaces owned strings" {
    const allocator = std.testing.allocator;
    const snapshots = try allocator.alloc(types.ObservationSnapshot, 0);
    defer allocator.free(snapshots);

    var fake = FakeDevice.init(allocator, snapshots);
    defer fake.deinit();

    try fake.install("/tmp/first.apk");
    try fake.install("/tmp/second.apk");
    try fake.launch();
    try fake.stop();
    try fake.clearState();
    const devices = try fake.listDevices();
    defer {
        for (devices) |device| device.deinit(allocator);
        allocator.free(devices);
    }
    try fake.openLink("exampleapp://probe");
    try fake.tap(10, 20);
    try fake.typeText("hello");
    try fake.eraseText(12);
    try fake.hideKeyboard();
    try fake.swipe(1, 2, 3, 4, 250);
    try fake.pressBack();

    try std.testing.expectEqualStrings("/tmp/second.apk", fake.installed_path.?);
    try std.testing.expect(fake.launched);
    try std.testing.expect(fake.stopped);
    try std.testing.expect(fake.cleared);
    try std.testing.expectEqualStrings("fake-device-1", devices[0].serial);
    try std.testing.expectEqualStrings("device", devices[0].state);
    try std.testing.expectEqualStrings("exampleapp://probe", fake.opened_link.?);
    try std.testing.expectEqual(@as(usize, 1), fake.taps);
    try std.testing.expectEqual(@as(usize, 1), fake.typed_text.items.len);
    try std.testing.expectEqualStrings("hello", fake.typed_text.items[0]);
    try std.testing.expectEqual(@as(usize, 1), fake.erases);
    try std.testing.expectEqual(@as(u32, 12), fake.last_erase_chars);
    try std.testing.expectEqual(@as(usize, 1), fake.hides_keyboard);
    try std.testing.expectEqual(@as(usize, 1), fake.swipes);
    try std.testing.expectEqual(@as(i32, 2), fake.last_swipe.?.y1);
    try std.testing.expectEqual(@as(usize, 1), fake.presses_back);
}

test "fake device snapshots are cloned with metadata and repeat last frame" {
    const allocator = std.testing.allocator;

    var nodes = try allocator.alloc(types.UiNode, 1);
    nodes[0] = .{
        .stable_id = try allocator.dupe(u8, "node-1"),
        .class_name = try allocator.dupe(u8, "android.widget.TextView"),
        .resource_id = try allocator.dupe(u8, "title"),
        .text = try allocator.dupe(u8, "Title"),
        .content_desc = try allocator.dupe(u8, "Readable title"),
        .bounds = .{ .x = 1, .y = 2, .width = 3, .height = 4 },
        .enabled = false,
        .visible = true,
        .selected = true,
    };

    var snapshots = try allocator.alloc(types.ObservationSnapshot, 2);
    snapshots[0] = .{
        .id = try allocator.dupe(u8, "snapshot-1"),
        .timestamp_ms = 10,
        .viewport = .{ .width = 1080, .height = 2400 },
        .active_package = try allocator.dupe(u8, "com.example.mobiletest"),
        .active_activity = try allocator.dupe(u8, ".MainActivity"),
        .screenshot_artifact = try allocator.dupe(u8, "screen.png"),
        .tree_artifact = try allocator.dupe(u8, "tree.xml"),
        .focused_node_id = try allocator.dupe(u8, "node-1"),
        .log_delta = try allocator.dupe(u8, "log line"),
        .nodes = nodes,
    };
    snapshots[1] = .{
        .id = try allocator.dupe(u8, "snapshot-2"),
        .timestamp_ms = 11,
        .nodes = try allocator.alloc(types.UiNode, 0),
    };
    defer {
        for (snapshots) |snap| snap.deinit(allocator);
        allocator.free(snapshots);
    }

    var fake = FakeDevice.init(allocator, snapshots);
    defer fake.deinit();

    var first = try fake.snapshot(null);
    defer first.deinit(allocator);
    try std.testing.expectEqualStrings("snapshot-1", first.id);
    try std.testing.expectEqualStrings("com.example.mobiletest", first.active_package.?);
    try std.testing.expectEqualStrings(".MainActivity", first.active_activity.?);
    try std.testing.expectEqualStrings("screen.png", first.screenshot_artifact.?);
    try std.testing.expectEqualStrings("tree.xml", first.tree_artifact.?);
    try std.testing.expectEqualStrings("node-1", first.focused_node_id.?);
    try std.testing.expectEqualStrings("log line", first.log_delta.?);
    try std.testing.expectEqualStrings("Title", first.nodes[0].text.?);
    try std.testing.expect(first.nodes[0].selected);

    var second = try fake.snapshot(null);
    defer second.deinit(allocator);
    var third = try fake.snapshot(null);
    defer third.deinit(allocator);
    try std.testing.expectEqualStrings("snapshot-2", second.id);
    try std.testing.expectEqualStrings("snapshot-2", third.id);
}
