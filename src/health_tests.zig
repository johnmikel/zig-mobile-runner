const std = @import("std");
const health = @import("health.zig");
const types = @import("types.zig");

test "health policy detects common mobile runtime overlays" {
    const nodes = [_]types.UiNode{
        .{
            .stable_id = "node-error",
            .class_name = "android.widget.TextView",
            .text = "Failed to connect to /10.0.2.2:8081",
        },
    };

    try std.testing.expect(health.hasUnhealthyOverlay(nodes[0..]));
}

test "health policy ignores ordinary app content" {
    const nodes = [_]types.UiNode{
        .{
            .stable_id = "node-home",
            .class_name = "android.widget.TextView",
            .text = "Welcome home",
        },
        .{
            .stable_id = "node-button",
            .class_name = "android.widget.Button",
            .text = "Continue",
        },
    };

    try std.testing.expect(!health.hasUnhealthyOverlay(nodes[0..]));
}
