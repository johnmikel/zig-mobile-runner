const std = @import("std");
const scenario_fields = @import("scenario_fields.zig");

test "scenario field helpers duplicate strings and parse selector arrays" {
    const allocator = std.testing.allocator;
    const json =
        \\{
        \\  "name": "field helpers",
        \\  "selector": {"text": "Continue"},
        \\  "selectors": [{"text": "A"}, {"id": "button-b"}],
        \\  "timeoutMs": 42,
        \\  "optional": true
        \\}
    ;
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();

    const object = parsed.value.object;
    const name = try scenario_fields.requiredString(allocator, object, "name");
    defer allocator.free(name);
    try std.testing.expectEqualStrings("field helpers", name);

    const timeout_ms = try scenario_fields.optionalU64(object, "timeoutMs", 5000);
    try std.testing.expectEqual(@as(u64, 42), timeout_ms);
    try std.testing.expect(try scenario_fields.optionalBool(object, "optional", false));

    var wanted = try scenario_fields.parseSelectorField(allocator, object);
    defer wanted.deinit(allocator);
    try std.testing.expectEqualStrings("Continue", wanted.text.?);

    const selectors = try scenario_fields.parseSelectorArrayField(allocator, object);
    defer {
        for (selectors) |item| item.deinit(allocator);
        allocator.free(selectors);
    }
    try std.testing.expectEqual(@as(usize, 2), selectors.len);
    try std.testing.expectEqualStrings("button-b", selectors[1].id.?);
}
