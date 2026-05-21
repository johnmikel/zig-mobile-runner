const std = @import("std");
const device_registry = @import("device_registry.zig");
const types = @import("types.zig");

test "ready states are platform specific" {
    try std.testing.expect(device_registry.isReady(.android, "device"));
    try std.testing.expect(!device_registry.isReady(.android, "offline"));
    try std.testing.expect(device_registry.isReady(.ios, "Booted"));
    try std.testing.expect(device_registry.isReady(.ios, "connected"));
    try std.testing.expect(!device_registry.isReady(.ios, "disconnected"));
    try std.testing.expect(!device_registry.isReady(.ios, "unavailable"));
}

test "json output includes portable ready values" {
    const allocator = std.testing.allocator;
    const devices = [_]types.DeviceInfo{
        .{ .serial = "ios-1", .state = "connected" },
        .{ .serial = "ios-2", .state = "unavailable" },
    };
    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);

    try device_registry.writeJson(out.writer(allocator), .ios, devices[0..]);

    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"platform\":\"ios\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"count\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"serial\":\"ios-1\",\"state\":\"connected\",\"ready\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"serial\":\"ios-2\",\"state\":\"unavailable\",\"ready\":false") != null);
}
