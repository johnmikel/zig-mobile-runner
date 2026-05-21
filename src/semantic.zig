const std = @import("std");
const trace = @import("trace.zig");
const types = @import("types.zig");

pub fn roleForNode(node: types.UiNode) []const u8 {
    if (classContains(node.class_name, "Button")) return "button";
    if (classContains(node.class_name, "EditText") or classContains(node.class_name, "TextField") or classContains(node.class_name, "SecureTextField")) return "textbox";
    if (classContains(node.class_name, "Switch")) return "switch";
    if (classContains(node.class_name, "CheckBox") or classContains(node.class_name, "Checkbox")) return "checkbox";
    if (classContains(node.class_name, "RadioButton")) return "radio";
    if (classContains(node.class_name, "Image")) return "image";
    if (classContains(node.class_name, "StaticText") or classContains(node.class_name, "TextView") or classContains(node.class_name, "Text")) return "text";
    if (node.content_desc != null or node.text != null) return "text";
    return "node";
}

pub fn accessibleName(node: types.UiNode) []const u8 {
    if (node.content_desc) |value| {
        if (value.len > 0) return value;
    }
    if (node.text) |value| {
        if (value.len > 0) return value;
    }
    if (node.resource_id) |value| {
        if (value.len > 0) return value;
    }
    return node.stable_id;
}

pub fn recommendedAction(node: types.UiNode) ?[]const u8 {
    if (!node.visible or !node.enabled) return null;
    const role = roleForNode(node);
    if (std.mem.eql(u8, role, "textbox")) return "type";
    if (std.mem.eql(u8, role, "button") or
        std.mem.eql(u8, role, "switch") or
        std.mem.eql(u8, role, "checkbox") or
        std.mem.eql(u8, role, "radio"))
    {
        return "tap";
    }
    return null;
}

pub fn isInteractive(node: types.UiNode) bool {
    return recommendedAction(node) != null;
}

pub fn writeSemanticSnapshotJson(writer: anytype, snapshot: types.ObservationSnapshot) !void {
    try writer.writeAll("{");
    try writer.writeAll("\"id\":");
    try trace.writeJsonString(writer, snapshot.id);
    try writer.print(",\"timestampMs\":{d}", .{snapshot.timestamp_ms});
    try writer.print(
        ",\"viewport\":{{\"width\":{d},\"height\":{d}}}",
        .{ snapshot.viewport.width, snapshot.viewport.height },
    );
    try writeNullableField(writer, "activePackage", snapshot.active_package);
    try writeNullableField(writer, "activeActivity", snapshot.active_activity);
    try writeNullableField(writer, "focusedNodeId", snapshot.focused_node_id);
    try writer.writeAll(",\"nodes\":[");

    var interactive_count: usize = 0;
    for (snapshot.nodes, 0..) |node, index| {
        if (index > 0) try writer.writeAll(",");
        if (isInteractive(node)) interactive_count += 1;
        try writeSemanticNodeJson(writer, node);
    }
    try writer.writeAll("],\"summary\":{");
    try writer.print("\"nodeCount\":{d},\"interactiveCount\":{d},\"visibleText\":[", .{ snapshot.nodes.len, interactive_count });
    var first_text = true;
    for (snapshot.nodes) |node| {
        if (!node.visible) continue;
        const text = visibleLabel(node) orelse continue;
        if (text.len == 0) continue;
        if (!first_text) try writer.writeAll(",");
        first_text = false;
        try trace.writeJsonString(writer, text);
    }
    try writer.writeAll("]}}");
}

fn writeSemanticNodeJson(writer: anytype, node: types.UiNode) !void {
    try writer.writeAll("{\"id\":");
    try trace.writeJsonString(writer, node.stable_id);
    try writer.writeAll(",\"role\":");
    try trace.writeJsonString(writer, roleForNode(node));
    try writer.writeAll(",\"name\":");
    try trace.writeJsonString(writer, accessibleName(node));
    try writer.writeAll(",\"selector\":");
    try writeBestSelectorJson(writer, node);
    try writer.writeAll(",\"source\":{");
    try writer.writeAll("\"className\":");
    try trace.writeJsonString(writer, node.class_name);
    try writeNullableField(writer, "resourceId", node.resource_id);
    try writeNullableField(writer, "text", node.text);
    try writeNullableField(writer, "contentDesc", node.content_desc);
    try writer.writeAll("},\"bounds\":");
    try writeBoundsJson(writer, node.bounds);
    try writer.print(
        ",\"enabled\":{},\"visible\":{},\"selected\":{},\"interactive\":{}",
        .{ node.enabled, node.visible, node.selected, isInteractive(node) },
    );
    try writer.writeAll(",\"recommendedAction\":");
    if (recommendedAction(node)) |action| {
        try trace.writeJsonString(writer, action);
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll("}");
}

fn writeBestSelectorJson(writer: anytype, node: types.UiNode) !void {
    try writer.writeAll("{");
    if (node.resource_id) |value| {
        if (value.len > 0) {
            try writer.writeAll("\"resourceId\":");
            try trace.writeJsonString(writer, value);
            try writer.writeAll("}");
            return;
        }
    }
    if (node.content_desc) |value| {
        if (value.len > 0) {
            try writer.writeAll("\"contentDesc\":");
            try trace.writeJsonString(writer, value);
            try writer.writeAll("}");
            return;
        }
    }
    if (node.text) |value| {
        if (value.len > 0) {
            try writer.writeAll("\"text\":");
            try trace.writeJsonString(writer, value);
            try writer.writeAll("}");
            return;
        }
    }
    try writer.writeAll("\"stableId\":");
    try trace.writeJsonString(writer, node.stable_id);
    try writer.writeAll("}");
}

fn writeBoundsJson(writer: anytype, bounds: types.Bounds) !void {
    try writer.print(
        "{{\"x\":{d},\"y\":{d},\"width\":{d},\"height\":{d},\"centerX\":{d},\"centerY\":{d}}}",
        .{ bounds.x, bounds.y, bounds.width, bounds.height, bounds.centerX(), bounds.centerY() },
    );
}

fn writeNullableField(writer: anytype, key: []const u8, value: ?[]const u8) !void {
    try writer.print(",\"{s}\":", .{key});
    if (value) |actual| {
        try trace.writeJsonString(writer, actual);
    } else {
        try writer.writeAll("null");
    }
}

fn visibleLabel(node: types.UiNode) ?[]const u8 {
    if (node.text) |value| {
        if (value.len > 0) return value;
    }
    if (node.content_desc) |value| {
        if (value.len > 0) return value;
    }
    return null;
}

fn classContains(class_name: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, class_name, needle) != null;
}
