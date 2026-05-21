const std = @import("std");
const types = @import("types.zig");

pub const Selector = struct {
    id: ?[]const u8 = null,
    text: ?[]const u8 = null,
    text_contains: ?[]const u8 = null,
    content_desc: ?[]const u8 = null,
    content_desc_contains: ?[]const u8 = null,
    class_name: ?[]const u8 = null,

    pub fn deinit(self: Selector, allocator: std.mem.Allocator) void {
        if (self.id) |value| allocator.free(value);
        if (self.text) |value| allocator.free(value);
        if (self.text_contains) |value| allocator.free(value);
        if (self.content_desc) |value| allocator.free(value);
        if (self.content_desc_contains) |value| allocator.free(value);
        if (self.class_name) |value| allocator.free(value);
    }

    pub fn clone(self: Selector, allocator: std.mem.Allocator) !Selector {
        return .{
            .id = try types.dupeOptional(allocator, self.id),
            .text = try types.dupeOptional(allocator, self.text),
            .text_contains = try types.dupeOptional(allocator, self.text_contains),
            .content_desc = try types.dupeOptional(allocator, self.content_desc),
            .content_desc_contains = try types.dupeOptional(allocator, self.content_desc_contains),
            .class_name = try types.dupeOptional(allocator, self.class_name),
        };
    }
};

pub fn matches(node: types.UiNode, wanted: Selector) bool {
    if (wanted.id) |id| {
        if (node.resource_id == null or !std.mem.eql(u8, node.resource_id.?, id)) return false;
    }
    if (wanted.text) |text| {
        if (node.text == null or !std.mem.eql(u8, node.text.?, text)) return false;
    }
    if (wanted.text_contains) |needle| {
        if (node.text == null or std.mem.indexOf(u8, node.text.?, needle) == null) return false;
    }
    if (wanted.content_desc) |desc| {
        if (node.content_desc == null or !std.mem.eql(u8, node.content_desc.?, desc)) return false;
    }
    if (wanted.content_desc_contains) |needle| {
        if (node.content_desc == null or std.mem.indexOf(u8, node.content_desc.?, needle) == null) return false;
    }
    if (wanted.class_name) |class_name| {
        if (!std.mem.eql(u8, node.class_name, class_name)) return false;
    }
    return node.visible;
}

pub fn find(nodes: []const types.UiNode, wanted: Selector) ?types.UiNode {
    for (nodes) |node| {
        if (matches(node, wanted)) return node;
    }
    return null;
}

pub fn parseFromJson(allocator: std.mem.Allocator, value: std.json.Value) !Selector {
    if (value != .object) return error.SelectorMustBeObject;
    const object = value.object;
    const id = try stringField(allocator, object, "id") orelse try stringField(allocator, object, "resourceId");
    return .{
        .id = id,
        .text = try stringField(allocator, object, "text"),
        .text_contains = try stringField(allocator, object, "textContains"),
        .content_desc = try stringField(allocator, object, "contentDesc"),
        .content_desc_contains = try stringField(allocator, object, "contentDescContains"),
        .class_name = try stringField(allocator, object, "className"),
    };
}

fn stringField(
    allocator: std.mem.Allocator,
    object: std.json.ObjectMap,
    key: []const u8,
) !?[]const u8 {
    const value = object.get(key) orelse return null;
    if (value != .string) return error.SelectorFieldMustBeString;
    return try allocator.dupe(u8, value.string);
}
