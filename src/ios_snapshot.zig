const std = @import("std");
const types = @import("types.zig");

pub fn parsePngViewport(bytes: []const u8) ?types.Viewport {
    const signature = "\x89PNG\r\n\x1a\n";
    if (bytes.len < 24 or !std.mem.eql(u8, bytes[0..8], signature)) return null;
    if (!std.mem.eql(u8, bytes[12..16], "IHDR")) return null;

    return .{
        .width = readBigEndianU32(bytes[16..20]),
        .height = readBigEndianU32(bytes[20..24]),
    };
}

fn readBigEndianU32(bytes: []const u8) u32 {
    return (@as(u32, bytes[0]) << 24) |
        (@as(u32, bytes[1]) << 16) |
        (@as(u32, bytes[2]) << 8) |
        @as(u32, bytes[3]);
}
