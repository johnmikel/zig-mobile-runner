const std = @import("std");
const types = @import("types.zig");

pub fn parseHierarchy(allocator: std.mem.Allocator, xml: []const u8) ![]types.UiNode {
    var nodes = std.ArrayList(types.UiNode).empty;
    errdefer {
        for (nodes.items) |node| node.deinit(allocator);
        nodes.deinit(allocator);
    }

    var cursor: usize = 0;
    var index: usize = 0;
    while (std.mem.indexOfPos(u8, xml, cursor, "<node")) |start| {
        const end = std.mem.indexOfScalarPos(u8, xml, start, '>') orelse break;
        const tag = xml[start..end];
        const class_name = try attrOwned(allocator, tag, "class") orelse try allocator.dupe(u8, "");
        errdefer allocator.free(class_name);
        const resource_id = try attrOwned(allocator, tag, "resource-id");
        errdefer if (resource_id) |value| allocator.free(value);
        var text = try attrOwned(allocator, tag, "text");
        errdefer if (text) |value| allocator.free(value);
        var content_desc = try attrOwned(allocator, tag, "content-desc");
        errdefer if (content_desc) |value| allocator.free(value);
        const bounds_text = try attrOwned(allocator, tag, "bounds");
        defer if (bounds_text) |value| allocator.free(value);

        const bounds = if (bounds_text) |value| parseBounds(value) catch types.Bounds{} else types.Bounds{};
        const enabled = parseBoolAttr(tag, "enabled", true);
        const selected = parseBoolAttr(tag, "selected", false);
        const visible = bounds.width > 0 and bounds.height > 0;
        text = emptyToNullOwned(allocator, text);
        content_desc = emptyToNullOwned(allocator, content_desc);
        const stable_id = try stableId(allocator, index, class_name, resource_id, text, content_desc, bounds);

        try nodes.append(allocator, .{
            .stable_id = stable_id,
            .class_name = class_name,
            .resource_id = resource_id,
            .text = text,
            .content_desc = content_desc,
            .bounds = bounds,
            .enabled = enabled,
            .visible = visible,
            .selected = selected,
        });

        index += 1;
        cursor = end + 1;
    }

    return try nodes.toOwnedSlice(allocator);
}

fn emptyToNullOwned(allocator: std.mem.Allocator, value: ?[]const u8) ?[]const u8 {
    if (value) |actual| {
        if (actual.len == 0) {
            allocator.free(actual);
            return null;
        }
    }
    return value;
}

fn attrOwned(allocator: std.mem.Allocator, tag: []const u8, name: []const u8) !?[]const u8 {
    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, tag, cursor, name)) |pos| {
        const eq = pos + name.len;
        if (eq + 1 < tag.len and tag[eq] == '=' and tag[eq + 1] == '"') {
            const value_start = eq + 2;
            const value_end = std.mem.indexOfScalarPos(u8, tag, value_start, '"') orelse return error.MalformedAttribute;
            return try xmlUnescape(allocator, tag[value_start..value_end]);
        }
        cursor = pos + name.len;
    }
    return null;
}

fn xmlUnescape(allocator: std.mem.Allocator, input: []const u8) ![]const u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    var i: usize = 0;
    while (i < input.len) {
        if (std.mem.startsWith(u8, input[i..], "&amp;")) {
            try out.append(allocator, '&');
            i += 5;
        } else if (std.mem.startsWith(u8, input[i..], "&lt;")) {
            try out.append(allocator, '<');
            i += 4;
        } else if (std.mem.startsWith(u8, input[i..], "&gt;")) {
            try out.append(allocator, '>');
            i += 4;
        } else if (std.mem.startsWith(u8, input[i..], "&quot;")) {
            try out.append(allocator, '"');
            i += 6;
        } else if (std.mem.startsWith(u8, input[i..], "&apos;")) {
            try out.append(allocator, '\'');
            i += 6;
        } else {
            try out.append(allocator, input[i]);
            i += 1;
        }
    }
    return try out.toOwnedSlice(allocator);
}

fn parseBoolAttr(tag: []const u8, name: []const u8, default_value: bool) bool {
    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, tag, cursor, name)) |pos| {
        const eq = pos + name.len;
        if (eq + 1 < tag.len and tag[eq] == '=' and tag[eq + 1] == '"') {
            const value_start = eq + 2;
            const value_end = std.mem.indexOfScalarPos(u8, tag, value_start, '"') orelse return default_value;
            return std.mem.eql(u8, tag[value_start..value_end], "true");
        }
        cursor = pos + name.len;
    }
    return default_value;
}

pub fn parseBounds(input: []const u8) !types.Bounds {
    if (input.len < 10 or input[0] != '[') return error.MalformedBounds;
    const comma_1 = std.mem.indexOfScalar(u8, input, ',') orelse return error.MalformedBounds;
    const close_1 = std.mem.indexOfScalarPos(u8, input, comma_1, ']') orelse return error.MalformedBounds;
    const open_2 = std.mem.indexOfScalarPos(u8, input, close_1, '[') orelse return error.MalformedBounds;
    const comma_2 = std.mem.indexOfScalarPos(u8, input, open_2, ',') orelse return error.MalformedBounds;
    const close_2 = std.mem.indexOfScalarPos(u8, input, comma_2, ']') orelse return error.MalformedBounds;

    const x1 = try std.fmt.parseInt(i32, input[1..comma_1], 10);
    const y1 = try std.fmt.parseInt(i32, input[comma_1 + 1 .. close_1], 10);
    const x2 = try std.fmt.parseInt(i32, input[open_2 + 1 .. comma_2], 10);
    const y2 = try std.fmt.parseInt(i32, input[comma_2 + 1 .. close_2], 10);

    return .{
        .x = x1,
        .y = y1,
        .width = @max(0, x2 - x1),
        .height = @max(0, y2 - y1),
    };
}

fn stableId(
    allocator: std.mem.Allocator,
    index: usize,
    class_name: []const u8,
    resource_id: ?[]const u8,
    text: ?[]const u8,
    content_desc: ?[]const u8,
    bounds: types.Bounds,
) ![]const u8 {
    if (resource_id) |value| {
        if (value.len > 0) return try std.fmt.allocPrint(allocator, "rid:{s}:{d}", .{ value, index });
    }
    if (content_desc) |value| {
        if (value.len > 0) return try std.fmt.allocPrint(allocator, "desc:{s}:{d}", .{ value, index });
    }
    if (text) |value| {
        if (value.len > 0) return try std.fmt.allocPrint(allocator, "text:{s}:{d}", .{ value, index });
    }
    return try std.fmt.allocPrint(
        allocator,
        "node:{s}:{d}:{d}:{d}:{d}:{d}",
        .{ class_name, bounds.x, bounds.y, bounds.width, bounds.height, index },
    );
}

test "parse uiautomator bounds" {
    const bounds = try parseBounds("[12,34][56,78]");
    try std.testing.expectEqual(@as(i32, 12), bounds.x);
    try std.testing.expectEqual(@as(i32, 34), bounds.y);
    try std.testing.expectEqual(@as(i32, 44), bounds.width);
    try std.testing.expectEqual(@as(i32, 44), bounds.height);
}

test "parse hierarchy nodes and unescape attrs" {
    const xml =
        \\<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
        \\<hierarchy rotation="0">
        \\  <node index="0" text="E2E &amp; auth" resource-id="probe" class="android.widget.TextView" package="com.example.mobiletest" content-desc="" checkable="false" checked="false" clickable="false" enabled="true" focusable="false" focused="false" scrollable="false" long-clickable="false" password="false" selected="false" bounds="[10,20][110,60]" />
        \\</hierarchy>
    ;
    const nodes = try parseHierarchy(std.testing.allocator, xml);
    defer {
        for (nodes) |node| node.deinit(std.testing.allocator);
        std.testing.allocator.free(nodes);
    }
    try std.testing.expectEqual(@as(usize, 1), nodes.len);
    try std.testing.expectEqualStrings("probe", nodes[0].resource_id.?);
    try std.testing.expectEqualStrings("E2E & auth", nodes[0].text.?);
    try std.testing.expectEqual(@as(i32, 100), nodes[0].bounds.width);
}

test "parse hierarchy handles desc ids selection invisibility and fallback ids" {
    const xml =
        \\<hierarchy>
        \\  <node index="0" text="" resource-id="" class="android.widget.ImageButton" content-desc="A &lt;quoted&gt; &quot;menu&quot; &apos;button&apos;" enabled="false" selected="true" bounds="[0,0][48,48]" />
        \\  <node index="1" text="Hidden" class="android.widget.TextView" enabled="true" selected="false" bounds="[4,4][4,20]" />
        \\  <node index="2" class="android.view.View" bounds="[5,6][7,8]" />
        \\</hierarchy>
    ;
    const nodes = try parseHierarchy(std.testing.allocator, xml);
    defer {
        for (nodes) |node| node.deinit(std.testing.allocator);
        std.testing.allocator.free(nodes);
    }

    try std.testing.expectEqual(@as(usize, 3), nodes.len);
    try std.testing.expect(nodes[0].text == null);
    try std.testing.expectEqualStrings("A <quoted> \"menu\" 'button'", nodes[0].content_desc.?);
    try std.testing.expectEqualStrings("desc:A <quoted> \"menu\" 'button':0", nodes[0].stable_id);
    try std.testing.expect(!nodes[0].enabled);
    try std.testing.expect(nodes[0].selected);
    try std.testing.expect(!nodes[1].visible);
    try std.testing.expect(std.mem.startsWith(u8, nodes[2].stable_id, "node:android.view.View:5:6:2:2:2"));
}

test "parse bounds rejects malformed input and clamps negative size" {
    try std.testing.expectError(error.MalformedBounds, parseBounds("bad"));
    const bounds = try parseBounds("[10,20][5,15]");
    try std.testing.expectEqual(@as(i32, 0), bounds.width);
    try std.testing.expectEqual(@as(i32, 0), bounds.height);
}
