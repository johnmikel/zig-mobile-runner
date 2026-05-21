const std = @import("std");
const doctor_hints = @import("doctor_hints.zig");

test "doctor hint policy maps tool failures to stable public setup codes" {
    try std.testing.expectEqualStrings("setup.zig.not_found", doctor_hints.setupErrorCode("zig", .missing));
    try std.testing.expectEqualStrings("setup.adb.command_failed", doctor_hints.setupErrorCode("adb", .warning));
    try std.testing.expectEqualStrings("setup.ios_shim.not_found", doctor_hints.setupErrorCode("ios-shim", .missing));
    try std.testing.expectEqualStrings("setup.tool.command_failed", doctor_hints.setupErrorCode("custom-tool", .warning));
}

test "doctor hint policy gives platform-specific remediation for app-local checks" {
    const allocator = std.testing.allocator;

    const config_hint = (try doctor_hints.hintForCheck(allocator, "config", .warning)).?;
    defer allocator.free(config_hint);
    try std.testing.expect(std.mem.indexOf(u8, config_hint, "zmr doctor --strict --json --config .zmr/config.json") != null);

    const android_hint = (try doctor_hints.hintForCheck(allocator, "android-smoke-scenario", .warning)).?;
    defer allocator.free(android_hint);
    try std.testing.expect(std.mem.indexOf(u8, android_hint, "android.smokeScenario") != null);

    const ios_hint = (try doctor_hints.hintForCheck(allocator, "ios-physical-devices", .warning)).?;
    defer allocator.free(ios_hint);
    try std.testing.expect(std.mem.indexOf(u8, ios_hint, "--ios-device-type physical") != null);
    try std.testing.expect(std.mem.indexOf(u8, ios_hint, "<physical-device-id>") != null);
    try std.testing.expect(std.mem.indexOf(u8, ios_hint, "<udid>") == null);

    try std.testing.expectEqual(@as(?[]const u8, null), try doctor_hints.hintForCheck(allocator, "zig", .ok));
}
