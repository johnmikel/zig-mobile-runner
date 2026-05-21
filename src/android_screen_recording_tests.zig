const std = @import("std");
const android_screen_recording = @import("android_screen_recording.zig");
const trace = @import("trace.zig");

test "android screen recording module starts stops and pulls trace artifact" {
    const allocator = std.testing.allocator;
    const dir = "zig-cache/test-android-screen-recording-module";
    std.fs.cwd().deleteTree(dir) catch {};
    defer std.fs.cwd().deleteTree(dir) catch {};

    var writer = try trace.TraceWriter.init(allocator, dir);
    defer writer.deinit();

    var recording = try android_screen_recording.start(
        allocator,
        "./tests/fake-adb.sh",
        "fake-android-1",
        "/sdcard/zmr-trace-screenrecord.mp4",
    );
    defer recording.deinit();

    const artifact_path = try recording.stopAndPull(&writer, "screenrecord.mp4");
    defer allocator.free(artifact_path);

    const bytes = try std.fs.cwd().readFileAlloc(allocator, artifact_path, 1024);
    defer allocator.free(bytes);
    try std.testing.expectEqualStrings("FAKE_MP4\n", bytes);
}
