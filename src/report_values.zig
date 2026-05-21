const std = @import("std");

pub fn stringField(object: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const value = object.get(key) orelse return null;
    if (value != .string) return null;
    return value.string;
}

pub fn intField(object: std.json.ObjectMap, key: []const u8) ?i64 {
    const value = object.get(key) orelse return null;
    return switch (value) {
        .integer => |actual| actual,
        else => null,
    };
}

pub fn meanDuration(durations: []const i64) i64 {
    if (durations.len == 0) return 0;
    var total: i64 = 0;
    for (durations) |duration| total += duration;
    return @divTrunc(total, @as(i64, @intCast(durations.len)));
}

pub fn percentile95(durations: []const i64) i64 {
    if (durations.len == 0) return 0;
    return durations[@as(usize, @intFromFloat(@floor(@as(f64, @floatFromInt(durations.len - 1)) * 0.95)))];
}
