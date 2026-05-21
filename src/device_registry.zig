const std = @import("std");
const trace = @import("trace.zig");
const types = @import("types.zig");

pub const Platform = enum {
    android,
    ios,
};

pub fn isReady(platform: Platform, state: []const u8) bool {
    return switch (platform) {
        .android => std.mem.eql(u8, state, "device"),
        .ios => std.mem.eql(u8, state, "Booted") or
            std.mem.eql(u8, state, "connected") or
            std.mem.eql(u8, state, "available"),
    };
}

pub fn isKnownReadyState(state: []const u8) bool {
    return isReady(.android, state) or isReady(.ios, state);
}

pub fn writeJson(writer: anytype, platform: Platform, devices: []const types.DeviceInfo) !void {
    try writer.writeAll("{\"platform\":");
    try trace.writeJsonString(writer, @tagName(platform));
    try writer.print(",\"count\":{d},\"devices\":[", .{devices.len});
    for (devices, 0..) |device, index| {
        if (index > 0) try writer.writeAll(",");
        try writer.writeAll("{\"serial\":");
        try trace.writeJsonString(writer, device.serial);
        try writer.writeAll(",\"state\":");
        try trace.writeJsonString(writer, device.state);
        try writer.print(",\"ready\":{}", .{isReady(platform, device.state)});
        try writer.writeAll("}");
    }
    try writer.writeAll("]}\n");
}
