const std = @import("std");
const cli_import = @import("cli_import.zig");

test "parse args rejects missing option values and unknown flags" {
    try std.testing.expectError(error.MissingImportOut, cli_import.parseArgs(&.{ "flow-yaml", "flow.yaml", "--out" }));
    try std.testing.expectError(error.MissingImportName, cli_import.parseArgs(&.{ "flow-yaml", "flow.yaml", "--name" }));
    try std.testing.expectError(error.MissingAppId, cli_import.parseArgs(&.{ "flow-yaml", "flow.yaml", "--app-id" }));
    try std.testing.expectError(error.UnknownFlag, cli_import.parseArgs(&.{ "flow-yaml", "flow.yaml", "--wat" }));
}
