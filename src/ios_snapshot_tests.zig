const std = @import("std");
const ios_snapshot = @import("ios_snapshot.zig");

test "ios snapshot parser reads png viewport from IHDR" {
    const png =
        "\x89PNG\r\n\x1a\n" ++
        "\x00\x00\x00\x0dIHDR" ++
        "\x00\x00\x00\x02" ++
        "\x00\x00\x00\x03" ++
        "\x08\x02\x00\x00\x00";

    const viewport = ios_snapshot.parsePngViewport(png).?;
    try std.testing.expectEqual(@as(u32, 2), viewport.width);
    try std.testing.expectEqual(@as(u32, 3), viewport.height);
}

test "ios snapshot parser rejects non png and incomplete ihdr bytes" {
    try std.testing.expect(ios_snapshot.parsePngViewport("not a png") == null);
    try std.testing.expect(ios_snapshot.parsePngViewport("\x89PNG\r\n\x1a\nshort") == null);
}
