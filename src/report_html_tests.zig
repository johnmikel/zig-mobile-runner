const std = @import("std");
const report_html = @import("report_html.zig");

test "report html helpers escape text and frame a valid document" {
    const allocator = std.testing.allocator;

    var body = std.ArrayList(u8).empty;
    defer body.deinit(allocator);
    try report_html.writeStart(body.writer(allocator), "A <B> \"C\"");
    try report_html.escape(body.writer(allocator), "Tom & <button> \"Run\"");
    try report_html.writeEnd(body.writer(allocator));

    try std.testing.expect(std.mem.indexOf(u8, body.items, "<!doctype html>") != null);
    try std.testing.expect(std.mem.indexOf(u8, body.items, "A &lt;B&gt; &quot;C&quot;") != null);
    try std.testing.expect(std.mem.indexOf(u8, body.items, "Tom &amp; &lt;button&gt; &quot;Run&quot;") != null);
    try std.testing.expect(std.mem.endsWith(u8, body.items, "</body></html>\n"));
}
