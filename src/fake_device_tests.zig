const std = @import("std");
const fake_device = @import("fake_device.zig");
const types = @import("types.zig");

test "fake device records commands and replaces owned strings" {
    const allocator = std.testing.allocator;
    const snapshots = try allocator.alloc(types.ObservationSnapshot, 0);
    defer allocator.free(snapshots);

    var fake = fake_device.FakeDevice.init(allocator, snapshots);
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

    var fake = fake_device.FakeDevice.init(allocator, snapshots);
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
