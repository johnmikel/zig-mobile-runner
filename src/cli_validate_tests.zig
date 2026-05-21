const std = @import("std");
const cli_validate = @import("cli_validate.zig");

test "parse args supports plain and json validation" {
    const plain = try cli_validate.parseArgs(&.{"scenario.json"});
    try std.testing.expectEqualStrings("scenario.json", plain.path);
    try std.testing.expect(!plain.json);

    const json = try cli_validate.parseArgs(&.{ "scenario.json", "--json" });
    try std.testing.expectEqualStrings("scenario.json", json.path);
    try std.testing.expect(json.json);
}
