const std = @import("std");
const json_fields = @import("json_fields.zig");

test "json field helpers parse typed params with caller-selected errors" {
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"text":"hello","count":7,"enabled":true}
    , .{});
    defer parsed.deinit();

    try std.testing.expectEqualStrings("hello", try json_fields.requiredString(parsed.value, "text", error.MissingParam, error.ParamMustBeString));
    try std.testing.expectEqual(@as(i32, 7), try json_fields.requiredI32(parsed.value, "count", error.MissingParam, error.ParamMustBeInteger));
    try std.testing.expectEqual(@as(u64, 7), try json_fields.optionalU64(parsed.value, "count", 3, error.ParamMustBeInteger));
    try std.testing.expectEqual(true, try json_fields.optionalBool(parsed.value, "enabled", false, error.ParamMustBeBool));
    try std.testing.expectEqual(@as(u64, 3), try json_fields.optionalU64(parsed.value, "missing", 3, error.ParamMustBeInteger));
}

test "json field helpers parse object fields with scenario-style errors" {
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"name":"probe","ms":500,"optional":false}
    , .{});
    defer parsed.deinit();
    const object = parsed.value.object;

    try std.testing.expectEqualStrings("probe", try json_fields.requiredStringFromObject(object, "name", error.RequiredStringMissing, error.RequiredFieldMustBeString));
    try std.testing.expectEqual(@as(u64, 500), try json_fields.optionalU64FromObject(object, "ms", 100, error.OptionalFieldMustBeInteger));
    try std.testing.expectEqual(false, try json_fields.optionalBoolFromObject(object, "optional", true, error.OptionalFieldMustBeBool));
    try std.testing.expectError(error.RequiredStringMissing, json_fields.requiredStringFromObject(object, "missing", error.RequiredStringMissing, error.RequiredFieldMustBeString));
}
