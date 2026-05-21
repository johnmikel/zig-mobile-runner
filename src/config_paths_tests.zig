const std = @import("std");
const config_paths = @import("config_paths.zig");

test "config paths resolve app-local files and command paths" {
    const allocator = std.testing.allocator;

    const root = try config_paths.rootForPath(allocator, "apps/sample/.zmr/config.json");
    defer allocator.free(root);
    try std.testing.expectEqualStrings("apps/sample", root);

    var owned = std.ArrayList([]const u8).empty;
    defer {
        for (owned.items) |path| allocator.free(path);
        owned.deinit(allocator);
    }

    const scenario_path = try config_paths.ownFilePath(allocator, &owned, root, ".zmr/android-smoke.json");
    try std.testing.expectEqualStrings("apps/sample/.zmr/android-smoke.json", scenario_path);

    const adb_path = try config_paths.ownCommandPath(allocator, &owned, root, "adb");
    try std.testing.expectEqualStrings("adb", adb_path);

    const shim_path = try config_paths.ownCommandPath(allocator, &owned, root, "./tools/ios-shim");
    try std.testing.expectEqualStrings("apps/sample/./tools/ios-shim", shim_path);
}
