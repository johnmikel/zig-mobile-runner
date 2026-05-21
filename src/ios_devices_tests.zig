const std = @import("std");
const ios_devices = @import("ios_devices.zig");

test "ios device discovery filters booted simulators" {
    const allocator = std.testing.allocator;
    const devices = try ios_devices.parseSimulatorsJson(allocator,
        \\{"devices":{"iOS 18.0":[
        \\{"udid":"booted","state":"Booted","isAvailable":true},
        \\{"udid":"shutdown","state":"Shutdown","isAvailable":true},
        \\{"udid":"unavailable","state":"Booted","isAvailable":false}
        \\]}}
    );
    defer {
        for (devices) |device| device.deinit(allocator);
        allocator.free(devices);
    }

    try std.testing.expectEqual(@as(usize, 1), devices.len);
    try std.testing.expectEqualStrings("booted", devices[0].serial);
}
