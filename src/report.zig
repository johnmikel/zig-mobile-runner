const std = @import("std");
const cli_output = @import("cli_output.zig");
const report_html = @import("report_html.zig");
const report_values = @import("report_values.zig");
const trace = @import("trace.zig");
const trace_summary = @import("trace_summary.zig");

pub fn writeHtmlReport(
    allocator: std.mem.Allocator,
    input_path: []const u8,
    out_path: []const u8,
) !void {
    const results_path = try std.fs.path.join(allocator, &.{ input_path, "results.jsonl" });
    defer allocator.free(results_path);

    if (std.fs.cwd().openFile(results_path, .{})) |file| {
        file.close();
        return try writeBenchmarkReport(allocator, input_path, results_path, out_path);
    } else |err| switch (err) {
        error.FileNotFound => return try writeTraceReport(allocator, input_path, out_path),
        else => return err,
    }
}

pub fn writeTraceExplanation(
    allocator: std.mem.Allocator,
    trace_dir: []const u8,
    writer: anytype,
) !void {
    var summary = try trace_summary.read(allocator, trace_dir);
    defer summary.deinit(allocator);
    try writeTraceExplanationText(writer, summary);
}

pub fn writeTraceExplanationJson(
    allocator: std.mem.Allocator,
    trace_dir: []const u8,
    writer: anytype,
) !void {
    var summary = try trace_summary.read(allocator, trace_dir);
    defer summary.deinit(allocator);
    try writeTraceExplanationJsonValue(writer, trace_dir, summary);
}

fn writeTraceExplanationText(writer: anytype, explanation: trace_summary.Summary) !void {
    try writer.writeAll("ZMR trace explanation\n");
    try writer.writeAll("scenario: ");
    try writer.writeAll(explanation.scenario_name);
    try writer.writeByte('\n');
    if (explanation.app_id) |value| {
        try writer.writeAll("appId: ");
        try writer.writeAll(value);
        try writer.writeByte('\n');
    }
    try writer.writeAll("status: ");
    try writer.writeAll(explanation.status);
    try writer.writeByte('\n');
    if (explanation.duration_ms) |value| try writer.print("durationMs: {d}\n", .{value});
    if (explanation.event_count) |value| try writer.print("events: {d}\n", .{value});
    if (explanation.snapshot_count) |value| try writer.print("snapshots: {d}\n", .{value});
    if (explanation.failed_step_index) |value| try writer.print("failedStepIndex: {d}\n", .{value});
    if (explanation.error_name) |value| {
        try writer.writeAll("error: ");
        try writer.writeAll(value);
        try writer.writeByte('\n');
    }
    if (explanation.diagnostic.kind) |kind| {
        try writer.writeAll("diagnostic: ");
        try writer.writeAll(kind);
        if (explanation.diagnostic.status) |value| {
            try writer.writeByte(' ');
            try writer.writeAll(value);
        }
        try writer.writeByte('\n');
    }
    if (explanation.diagnostic.artifact_status) |value| {
        try writer.writeAll("artifactStatus: ");
        try writer.writeAll(value);
        try writer.writeByte('\n');
    }
    if (explanation.diagnostic.semantic_status) |value| {
        try writer.writeAll("semanticStatus: ");
        try writer.writeAll(value);
        try writer.writeByte('\n');
    }
    if (explanation.diagnostic.snapshot_id) |value| {
        try writer.writeAll("snapshot: ");
        try writer.writeAll(value);
        try writer.writeByte('\n');
    }
    if (explanation.diagnostic.active_package) |value| {
        try writer.writeAll("activePackage: ");
        try writer.writeAll(value);
        try writer.writeByte('\n');
    }
    if (explanation.diagnostic.active_activity) |value| {
        try writer.writeAll("activeActivity: ");
        try writer.writeAll(value);
        try writer.writeByte('\n');
    }
    if (explanation.diagnostic.visible_texts) |value| {
        try writer.writeAll("visibleTexts: ");
        try writer.writeAll(value);
        try writer.writeByte('\n');
    }
    if (explanation.diagnostic.nearest_matches) |value| {
        try writer.writeAll("nearestTextMatches: ");
        try writer.writeAll(value);
        try writer.writeByte('\n');
    }
    if (explanation.last_kind) |value| {
        try writer.writeAll("lastEvent: ");
        try writer.writeAll(value);
        try writer.writeByte('\n');
    }
}

fn writeTraceExplanationJsonValue(writer: anytype, trace_dir: []const u8, explanation: trace_summary.Summary) !void {
    try writer.writeAll("{\"ok\":true,\"traceDir\":");
    try trace.writeJsonString(writer, trace_dir);
    try writer.writeAll(",\"scenario\":");
    try trace.writeJsonString(writer, explanation.scenario_name);
    try writer.writeAll(",\"status\":");
    try trace.writeJsonString(writer, explanation.status);
    if (explanation.app_id) |value| {
        try writer.writeAll(",\"appId\":");
        try trace.writeJsonString(writer, value);
    }
    if (explanation.duration_ms) |value| try writer.print(",\"durationMs\":{d}", .{value});
    if (explanation.event_count) |value| try writer.print(",\"eventCount\":{d}", .{value});
    if (explanation.snapshot_count) |value| try writer.print(",\"snapshotCount\":{d}", .{value});
    if (explanation.failed_step_index) |value| try writer.print(",\"failedStepIndex\":{d}", .{value});
    if (explanation.error_name) |value| {
        try writer.writeAll(",\"error\":");
        try trace.writeJsonString(writer, value);
    }
    if (explanation.diagnostic.kind) |_| {
        try writer.writeAll(",\"diagnostic\":");
        try trace_summary.writeDiagnosticJson(writer, explanation.diagnostic);
    }
    if (explanation.last_kind) |value| {
        try writer.writeAll(",\"lastEvent\":");
        try trace.writeJsonString(writer, value);
    }
    try writeTraceExplanationNextCommandsJson(writer, trace_dir);
    try writer.writeAll("}\n");
}

fn writeTraceExplanationNextCommandsJson(writer: anytype, trace_dir: []const u8) !void {
    try writer.writeAll(",\"nextCommands\":[\"zmr report ");
    try cli_output.writeShellArgJsonContent(writer, trace_dir);
    try writer.writeAll(" --out ");
    try cli_output.writeJoinedPathShellArgJsonContent(writer, trace_dir, "report.html");
    try writer.writeAll("\",\"zmr export ");
    try cli_output.writeShellArgJsonContent(writer, trace_dir);
    try writer.writeAll(" --out ");
    try cli_output.writePathWithSuffixShellArgJsonContent(writer, trace_dir, ".zmrtrace");
    try writer.writeAll(" --redact\"]");
}

fn writeBenchmarkReport(
    allocator: std.mem.Allocator,
    input_path: []const u8,
    results_path: []const u8,
    out_path: []const u8,
) !void {
    const content = try std.fs.cwd().readFileAlloc(allocator, results_path, 64 * 1024 * 1024);
    defer allocator.free(content);

    var rows_html = std.ArrayList(u8).empty;
    defer rows_html.deinit(allocator);
    var durations = std.ArrayList(i64).empty;
    defer durations.deinit(allocator);

    var total: usize = 0;
    var passed: usize = 0;
    var failed: usize = 0;

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r\n");
        if (line.len == 0) continue;

        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, line, .{});
        defer parsed.deinit();
        if (parsed.value != .object) continue;
        const object = parsed.value.object;

        const tool = report_values.stringField(object, "tool") orelse "";
        const status = report_values.stringField(object, "status") orelse "";
        const trace_status = report_values.stringField(object, "traceStatus") orelse "";
        const trace_error = report_values.stringField(object, "traceError") orelse "";
        const trace_dir = report_values.stringField(object, "traceDir") orelse "";
        const run = report_values.intField(object, "run") orelse 0;
        const duration_ms = report_values.intField(object, "durationMs") orelse 0;
        const failed_step = report_values.intField(object, "failedStepIndex");

        total += 1;
        if (duration_ms >= 0) try durations.append(allocator, duration_ms);
        const row_passed = std.mem.eql(u8, status, "ok") and (trace_status.len == 0 or std.mem.eql(u8, trace_status, "passed"));
        if (row_passed) {
            passed += 1;
        } else {
            failed += 1;
        }

        const writer = rows_html.writer(allocator);
        try writer.writeAll("<tr><td>");
        try writer.print("{d}", .{run});
        try writer.writeAll("</td><td>");
        try report_html.escape(writer, tool);
        try writer.writeAll("</td><td class=\"");
        try writer.writeAll(if (row_passed) "ok" else "failed");
        try writer.writeAll("\">");
        try report_html.escape(writer, status);
        try writer.writeAll("</td><td>");
        try writer.print("{d}", .{duration_ms});
        try writer.writeAll("</td><td>");
        try report_html.escape(writer, trace_status);
        try writer.writeAll("</td><td>");
        if (failed_step) |index| {
            try writer.print("failedStepIndex={d}", .{index});
        }
        if (trace_error.len > 0) {
            if (failed_step != null) try writer.writeAll(" ");
            try report_html.escape(writer, trace_error);
        }
        try writer.writeAll("</td><td>");
        if (trace_dir.len > 0) {
            const events_path = try std.fs.path.join(allocator, &.{ trace_dir, "events.jsonl" });
            defer allocator.free(events_path);
            try report_html.writeArtifactLink(allocator, writer, events_path, "events.jsonl");
        }
        try writer.writeAll("</td></tr>\n");
    }

    std.mem.sort(i64, durations.items, {}, std.sort.asc(i64));
    const mean = report_values.meanDuration(durations.items);
    const p95 = report_values.percentile95(durations.items);

    var html = std.ArrayList(u8).empty;
    defer html.deinit(allocator);
    const writer = html.writer(allocator);
    try report_html.writeStart(writer, "ZMR Report");
    try writer.writeAll("<h1>ZMR Report</h1>\n");
    try writer.writeAll("<p class=\"muted\">Source: ");
    try report_html.escape(writer, input_path);
    try writer.writeAll("</p>\n");
    try writer.writeAll("<section><h2>Benchmark Summary</h2><dl>");
    try writer.print("<dt>Pass Rate</dt><dd>{d}/{d}</dd>", .{ passed, total });
    try writer.print("<dt>Failures</dt><dd>{d}</dd>", .{failed});
    try writer.print("<dt>Mean</dt><dd>{d}ms</dd>", .{mean});
    try writer.print("<dt>P95</dt><dd>{d}ms</dd>", .{p95});
    try writer.writeAll("</dl></section>\n");
    try writer.writeAll("<section><h2>Runs</h2><table><thead><tr><th>Run</th><th>Tool</th><th>Status</th><th>Duration</th><th>Trace Status</th><th>Failure</th><th>Artifacts</th></tr></thead><tbody>\n");
    try writer.writeAll(rows_html.items);
    try writer.writeAll("</tbody></table></section>\n");
    try writer.writeAll("<p class=\"warning\">Screenshots and raw UI XML may contain app data. Sanitize trace bundles before public sharing.</p>\n");
    try report_html.writeEnd(writer);
    try report_html.writeFile(out_path, html.items);
}

fn writeTraceReport(
    allocator: std.mem.Allocator,
    input_path: []const u8,
    out_path: []const u8,
) !void {
    const events_path = try std.fs.path.join(allocator, &.{ input_path, "events.jsonl" });
    defer allocator.free(events_path);
    const content = try std.fs.cwd().readFileAlloc(allocator, events_path, 64 * 1024 * 1024);
    defer allocator.free(content);

    var events_html = std.ArrayList(u8).empty;
    defer events_html.deinit(allocator);
    var total: usize = 0;
    var terminal_status: ?[]u8 = null;
    defer if (terminal_status) |value| allocator.free(value);
    var terminal_error: ?[]u8 = null;
    defer if (terminal_error) |value| allocator.free(value);

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r\n");
        if (line.len == 0) continue;

        const parsed = try std.json.parseFromSlice(std.json.Value, allocator, line, .{});
        defer parsed.deinit();
        if (parsed.value != .object) continue;
        const object = parsed.value.object;
        const seq = report_values.intField(object, "seq") orelse @as(i64, @intCast(total + 1));
        const kind = report_values.stringField(object, "kind") orelse "";
        if (std.mem.eql(u8, kind, "scenario.end")) {
            if (object.get("payload")) |payload| {
                if (payload == .object) {
                    if (report_values.stringField(payload.object, "status")) |value| {
                        if (terminal_status) |old| allocator.free(old);
                        terminal_status = try allocator.dupe(u8, value);
                    }
                    if (report_values.stringField(payload.object, "error")) |value| {
                        if (terminal_error) |old| allocator.free(old);
                        terminal_error = try allocator.dupe(u8, value);
                    }
                }
            }
        }

        total += 1;
        const writer = events_html.writer(allocator);
        try writer.writeAll("<tr><td>");
        try writer.print("{d}", .{seq});
        try writer.writeAll("</td><td>");
        try report_html.escape(writer, kind);
        try writer.writeAll("</td><td><code>");
        try report_html.escape(writer, line);
        try writer.writeAll("</code></td></tr>\n");
    }

    var html = std.ArrayList(u8).empty;
    defer html.deinit(allocator);
    const writer = html.writer(allocator);
    try report_html.writeStart(writer, "ZMR Trace Report");
    try writer.writeAll("<h1>ZMR Trace Report</h1>\n");
    try writer.writeAll("<p class=\"muted\">Source: ");
    try report_html.escape(writer, input_path);
    try writer.writeAll("</p>\n");
    try writer.writeAll("<section><h2>Trace Summary</h2><dl>");
    try writer.print("<dt>Events</dt><dd>{d}</dd>", .{total});
    try writer.writeAll("<dt>Terminal Status</dt><dd>");
    try report_html.escape(writer, terminal_status orelse "");
    try writer.writeAll("</dd><dt>Error</dt><dd>");
    try report_html.escape(writer, terminal_error orelse "");
    try writer.writeAll("</dd></dl></section>\n");
    try writer.writeAll("<section><h2>Timeline</h2><table><thead><tr><th>Seq</th><th>Kind</th><th>Event</th></tr></thead><tbody>\n");
    try writer.writeAll(events_html.items);
    try writer.writeAll("</tbody></table></section>\n");
    try writer.writeAll("<p>");
    try report_html.writeArtifactLink(allocator, writer, events_path, "events.jsonl");
    try writer.writeAll("</p>\n");
    try writer.writeAll("<p class=\"warning\">Screenshots and raw UI XML may contain app data. Sanitize trace bundles before public sharing.</p>\n");
    try report_html.writeEnd(writer);
    try report_html.writeFile(out_path, html.items);

    const relative_report_path = std.fs.path.relative(allocator, input_path, out_path) catch try allocator.dupe(u8, out_path);
    defer allocator.free(relative_report_path);
    try trace.attachReportPath(allocator, input_path, relative_report_path);
}
