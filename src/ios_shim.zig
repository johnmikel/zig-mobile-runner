const std = @import("std");
const trace = @import("trace.zig");
const types = @import("types.zig");

pub const CommandKind = enum {
    snapshot,
    tap,
    type_text,
    erase_text,
    hide_keyboard,
    swipe,
    press_back,
    app_state,
    settle,
};

pub const Command = struct {
    kind: CommandKind,
    selector: ?[]const u8 = null,
    text: ?[]const u8 = null,
    x: ?i32 = null,
    y: ?i32 = null,
    x1: ?i32 = null,
    y1: ?i32 = null,
    x2: ?i32 = null,
    y2: ?i32 = null,
    duration_ms: ?u32 = null,
    max_chars: ?u32 = null,
};

pub fn writeCommandJson(writer: anytype, command: Command) !void {
    try writer.writeAll("{\"cmd\":");
    try trace.writeJsonString(writer, commandName(command.kind));
    if (command.selector) |selector| {
        try writer.writeAll(",\"selector\":");
        try trace.writeJsonString(writer, selector);
    }
    if (command.text) |text| {
        try writer.writeAll(",\"text\":");
        try trace.writeJsonString(writer, text);
    }
    if (command.x) |value| try writer.print(",\"x\":{d}", .{value});
    if (command.y) |value| try writer.print(",\"y\":{d}", .{value});
    if (command.x1) |value| try writer.print(",\"x1\":{d}", .{value});
    if (command.y1) |value| try writer.print(",\"y1\":{d}", .{value});
    if (command.x2) |value| try writer.print(",\"x2\":{d}", .{value});
    if (command.y2) |value| try writer.print(",\"y2\":{d}", .{value});
    if (command.duration_ms) |value| try writer.print(",\"durationMs\":{d}", .{value});
    if (command.max_chars) |value| try writer.print(",\"maxChars\":{d}", .{value});
    try writer.writeAll("}\n");
}

pub fn parseSnapshotNodes(allocator: std.mem.Allocator, content: []const u8) ![]types.UiNode {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, content, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.IosShimResponseMustBeObject;
    const status = fieldString(parsed.value.object, "status") orelse return error.IosShimMissingStatus;
    if (!std.mem.eql(u8, status, "ok")) return error.IosShimResponseNotOk;
    const nodes_value = parsed.value.object.get("nodes") orelse return error.IosShimMissingNodes;
    if (nodes_value != .array) return error.IosShimNodesMustBeArray;

    var nodes = std.ArrayList(types.UiNode).empty;
    errdefer {
        for (nodes.items) |*node| node.deinit(allocator);
        nodes.deinit(allocator);
    }

    for (nodes_value.array.items) |node_value| {
        if (node_value != .object) return error.IosShimNodeMustBeObject;
        const object = node_value.object;
        const stable_id_source = fieldString(object, "id") orelse return error.IosShimNodeMissingId;
        const class_name_source = fieldString(object, "type") orelse "XCUIElementTypeOther";
        const bounds_value = object.get("bounds") orelse return error.IosShimNodeMissingBounds;
        if (bounds_value != .object) return error.IosShimBoundsMustBeObject;

        const text = fieldString(object, "label") orelse fieldString(object, "value");
        const content_desc = fieldString(object, "identifier");
        try nodes.append(allocator, .{
            .stable_id = try allocator.dupe(u8, stable_id_source),
            .class_name = try allocator.dupe(u8, class_name_source),
            .text = try dupeOptional(allocator, text),
            .content_desc = try dupeOptional(allocator, content_desc),
            .resource_id = try dupeOptional(allocator, content_desc),
            .bounds = .{
                .x = try intField(bounds_value.object, "x"),
                .y = try intField(bounds_value.object, "y"),
                .width = try intField(bounds_value.object, "width"),
                .height = try intField(bounds_value.object, "height"),
            },
            .enabled = boolField(object, "enabled", true),
            .visible = boolField(object, "visible", true),
            .selected = boolField(object, "selected", false),
        });
    }

    return try nodes.toOwnedSlice(allocator);
}

pub fn parseOkResponse(content: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const parsed = try std.json.parseFromSlice(std.json.Value, arena.allocator(), content, .{});
    if (parsed.value != .object) return error.IosShimResponseMustBeObject;
    const status = fieldString(parsed.value.object, "status") orelse return error.IosShimMissingStatus;
    if (!std.mem.eql(u8, status, "ok")) return error.IosShimResponseNotOk;
}

fn commandName(kind: CommandKind) []const u8 {
    return switch (kind) {
        .snapshot => "snapshot",
        .tap => "tap",
        .type_text => "type",
        .erase_text => "eraseText",
        .hide_keyboard => "hideKeyboard",
        .swipe => "swipe",
        .press_back => "pressBack",
        .app_state => "appState",
        .settle => "settle",
    };
}

fn fieldString(object: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const value = object.get(key) orelse return null;
    if (value != .string) return null;
    return value.string;
}

fn boolField(object: std.json.ObjectMap, key: []const u8, default: bool) bool {
    const value = object.get(key) orelse return default;
    if (value != .bool) return default;
    return value.bool;
}

fn intField(object: std.json.ObjectMap, key: []const u8) !i32 {
    const value = object.get(key) orelse return error.IosShimBoundsMissingField;
    if (value != .integer) return error.IosShimBoundsFieldMustBeInteger;
    if (value.integer < std.math.minInt(i32) or value.integer > std.math.maxInt(i32)) return error.IosShimBoundsFieldMustBeInteger;
    return @intCast(value.integer);
}

fn dupeOptional(allocator: std.mem.Allocator, value: ?[]const u8) !?[]const u8 {
    if (value) |actual| return try allocator.dupe(u8, actual);
    return null;
}

test "ios shim command json is stable" {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(std.testing.allocator);
    try writeCommandJson(out.writer(std.testing.allocator), .{
        .kind = .tap,
        .selector = "text=Continue",
        .x = 20,
        .y = 40,
    });
    try std.testing.expectEqualStrings("{\"cmd\":\"tap\",\"selector\":\"text=Continue\",\"x\":20,\"y\":40}\n", out.items);
}

test "ios shim snapshot response maps xctest elements into ui nodes" {
    const content =
        \\{
        \\  "status": "ok",
        \\  "nodes": [
        \\    {
        \\      "id": "button-continue",
        \\      "type": "XCUIElementTypeButton",
        \\      "label": "Continue",
        \\      "identifier": "continue_button",
        \\      "bounds": { "x": 10, "y": 20, "width": 100, "height": 44 },
        \\      "enabled": true,
        \\      "visible": true,
        \\      "selected": false
        \\    }
        \\  ]
        \\}
    ;

    const nodes = try parseSnapshotNodes(std.testing.allocator, content);
    defer {
        for (nodes) |*node| node.deinit(std.testing.allocator);
        std.testing.allocator.free(nodes);
    }

    try std.testing.expectEqual(@as(usize, 1), nodes.len);
    try std.testing.expectEqualStrings("button-continue", nodes[0].stable_id);
    try std.testing.expectEqualStrings("XCUIElementTypeButton", nodes[0].class_name);
    try std.testing.expectEqualStrings("Continue", nodes[0].text.?);
    try std.testing.expectEqualStrings("continue_button", nodes[0].content_desc.?);
    try std.testing.expectEqual(@as(i32, 10), nodes[0].bounds.x);
    try std.testing.expect(nodes[0].enabled);
    try std.testing.expect(nodes[0].visible);
}

test "ios shim rejects malformed snapshot responses" {
    try std.testing.expectError(error.IosShimMissingStatus, parseSnapshotNodes(std.testing.allocator, "{}"));
    try std.testing.expectError(error.IosShimResponseNotOk, parseSnapshotNodes(std.testing.allocator,
        \\{"status":"error","message":"no app"}
    ));
}

test "ios shim parses action ok and error responses" {
    try parseOkResponse("{\"status\":\"ok\"}\n");
    try std.testing.expectError(error.IosShimResponseNotOk, parseOkResponse("{\"status\":\"error\",\"message\":\"miss\"}\n"));
    try std.testing.expectError(error.IosShimMissingStatus, parseOkResponse("{}"));
}
