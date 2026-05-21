const std = @import("std");
const bundle_redaction = @import("bundle_redaction.zig");

test "bundle redaction scrubs json text and classifies visual artifacts" {
    const allocator = std.testing.allocator;

    const redacted_json = try bundle_redaction.redactEntry(
        allocator,
        "artifacts/snapshot-1.json",
        "{\"email\":\"agent@example.com\",\"authToken\":\"abc.def.ghi\",\"label\":\"Dashboard\"}",
        .{},
    );
    defer allocator.free(redacted_json);
    try std.testing.expect(std.mem.indexOf(u8, redacted_json, "agent@example.com") == null);
    try std.testing.expect(std.mem.indexOf(u8, redacted_json, "[REDACTED:email]") != null);
    try std.testing.expect(std.mem.indexOf(u8, redacted_json, "[REDACTED:secret]") != null);
    try std.testing.expect(std.mem.indexOf(u8, redacted_json, "Dashboard") != null);

    const redacted_xml = try bundle_redaction.redactEntry(
        allocator,
        "artifacts/snapshot-1.xml",
        "<node resource-id=\"password-field\" text=\"hunter2\" /><node text=\"agent@example.com\" />",
        .{},
    );
    defer allocator.free(redacted_xml);
    try std.testing.expect(std.mem.indexOf(u8, redacted_xml, "hunter2") == null);
    try std.testing.expect(std.mem.indexOf(u8, redacted_xml, "agent@example.com") == null);

    try std.testing.expect(bundle_redaction.isPlaceholderScreenshotPath("artifacts/snapshot-1.png"));
    try std.testing.expect(bundle_redaction.isVisualArtifactPath("artifacts/screenrecord.mp4"));
    try std.testing.expect(!bundle_redaction.isVisualArtifactPath("events.jsonl"));
}
