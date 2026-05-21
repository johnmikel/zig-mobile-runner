const std = @import("std");
const cli_trace = @import("cli_trace.zig");

test "parse args rejects missing values and unknown flags" {
    try std.testing.expectError(error.MissingReportOutput, cli_trace.parseReportArgs(&.{"traces/run"}));
    try std.testing.expectError(error.MissingReportOutput, cli_trace.parseReportArgs(&.{ "traces/run", "--out" }));
    try std.testing.expectError(error.UnknownFlag, cli_trace.parseReportArgs(&.{ "traces/run", "--wat" }));

    try std.testing.expectError(error.UnknownFlag, cli_trace.parseExplainArgs(&.{ "traces/run", "extra" }));

    try std.testing.expectError(error.MissingTraceDir, cli_trace.parseExportArgs(&.{}));
    try std.testing.expectError(error.MissingTraceBundleOutput, cli_trace.parseExportArgs(&.{ "traces/run", "--out" }));
    try std.testing.expectError(error.UnknownFlag, cli_trace.parseExportArgs(&.{ "traces/run", "--wat" }));
}
