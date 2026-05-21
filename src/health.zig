const std = @import("std");
const selector = @import("selector.zig");
const types = @import("types.zig");

const default_selectors = [_]selector.Selector{
    .{ .text_contains = "Uncaught Error" },
    .{ .text_contains = "Application has crashed" },
    .{ .text_contains = "This development build encountered the following error" },
    .{ .text_contains = "There was a problem loading the project" },
    .{ .text_contains = "Failed to connect" },
    .{ .text_contains = "Could not connect to development server" },
    .{ .text_contains = "Unable to load script" },
    .{ .text_contains = "Invariant Violation" },
    .{ .text_contains = "ReferenceError" },
    .{ .text_contains = "TypeError" },
    .{ .text_contains = "SyntaxError" },
};

pub fn defaultSelectors() []const selector.Selector {
    return default_selectors[0..];
}

pub fn hasUnhealthyOverlay(nodes: []const types.UiNode) bool {
    for (defaultSelectors()) |wanted| {
        if (selector.find(nodes, wanted) != null) return true;
    }
    return false;
}
