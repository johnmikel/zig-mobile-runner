const std = @import("std");
const json_rpc_params = @import("json_rpc_params.zig");

test "json rpc params parse required optional and direction fields" {
    const allocator = std.testing.allocator;
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator,
        \\{"url":"exampleapp://probe","timeoutMs":2500,"redact":true,"direction":"up","x1":42}
    , .{});
    defer parsed.deinit();

    try std.testing.expectEqualStrings("exampleapp://probe", try json_rpc_params.requiredString(parsed.value, "url"));
    try std.testing.expectEqual(@as(u64, 2500), try json_rpc_params.optionalU64(parsed.value, "timeoutMs", 5000));
    try std.testing.expectEqual(true, try json_rpc_params.optionalBool(parsed.value, "redact", false));
    try std.testing.expectEqual(@as(i32, 42), try json_rpc_params.requiredI32(parsed.value, "x1"));
    try std.testing.expectEqual(.up, try json_rpc_params.optionalDirection(parsed.value, "direction", .down));
    try std.testing.expectEqual(@as(u64, 7), try json_rpc_params.optionalU64(parsed.value, "missing", 7));
}

test "json rpc params parse selector arrays and reject empty arrays" {
    const allocator = std.testing.allocator;
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator,
        \\{"selectors":[{"text":"Login"},{"resourceId":"submit"}]}
    , .{});
    defer parsed.deinit();

    const selectors = try json_rpc_params.selectors(allocator, parsed.value);
    defer {
        for (selectors) |wanted| wanted.deinit(allocator);
        allocator.free(selectors);
    }
    try std.testing.expectEqual(@as(usize, 2), selectors.len);

    const empty = try std.json.parseFromSlice(std.json.Value, allocator, "{\"selectors\":[]}", .{});
    defer empty.deinit();
    try std.testing.expectError(error.SelectorsMustNotBeEmpty, json_rpc_params.selectors(allocator, empty.value));
}
