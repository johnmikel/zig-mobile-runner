const std = @import("std");
const report_values = @import("report_values.zig");

test "report value helpers read fields and summarize sorted durations" {
    const allocator = std.testing.allocator;
    const json =
        \\{"tool":"zmr","run":7,"durationMs":300,"ignored":true}
    ;
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();

    const object = parsed.value.object;
    try std.testing.expectEqualStrings("zmr", report_values.stringField(object, "tool").?);
    try std.testing.expectEqual(@as(i64, 7), report_values.intField(object, "run").?);
    try std.testing.expect(report_values.stringField(object, "missing") == null);
    try std.testing.expect(report_values.intField(object, "tool") == null);

    const durations = [_]i64{ 100, 200, 300, 400, 500 };
    try std.testing.expectEqual(@as(i64, 300), report_values.meanDuration(&durations));
    try std.testing.expectEqual(@as(i64, 400), report_values.percentile95(&durations));
    try std.testing.expectEqual(@as(i64, 0), report_values.meanDuration(&.{}));
    try std.testing.expectEqual(@as(i64, 0), report_values.percentile95(&.{}));
}
