const std = @import("std");
const types = @import("types.zig");

test "bounds center uses integer midpoint" {
    const b = types.Bounds{ .x = 10, .y = 20, .width = 21, .height = 19 };
    try std.testing.expectEqual(@as(i32, 20), b.centerX());
    try std.testing.expectEqual(@as(i32, 29), b.centerY());
}
