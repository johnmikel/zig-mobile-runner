const std = @import("std");
const trace = @import("trace.zig");

const TraceExplanation = struct {
    scenario_name: []u8,
    status: []u8,
    app_id: ?[]u8 = null,
    duration_ms: ?i64 = null,
    event_count: ?i64 = null,
    snapshot_count: ?i64 = null,
    failed_step_index: ?i64 = null,
    error_name: ?[]u8 = null,
    diagnostic: DiagnosticEvent = .{},
    last_kind: ?[]u8 = null,

    fn deinit(self: *TraceExplanation, allocator: std.mem.Allocator) void {
        allocator.free(self.scenario_name);
        allocator.free(self.status);
        if (self.app_id) |value| allocator.free(value);
        if (self.error_name) |value| allocator.free(value);
        self.diagnostic.deinit(allocator);
        if (self.last_kind) |value| allocator.free(value);
    }
};

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
    var explanation = try readTraceExplanation(allocator, trace_dir);
    defer explanation.deinit(allocator);
    try writeTraceExplanationText(writer, explanation);
}

pub fn writeTraceExplanationJson(
    allocator: std.mem.Allocator,
    trace_dir: []const u8,
    writer: anytype,
) !void {
    var explanation = try readTraceExplanation(allocator, trace_dir);
    defer explanation.deinit(allocator);
    try writeTraceExplanationJsonValue(writer, explanation);
}

fn readTraceExplanation(
    allocator: std.mem.Allocator,
    trace_dir: []const u8,
) !TraceExplanation {
    const manifest_path = try std.fs.path.join(allocator, &.{ trace_dir, "trace.json" });
    defer allocator.free(manifest_path);
    const manifest_content = try std.fs.cwd().readFileAlloc(allocator, manifest_path, 1024 * 1024);
    defer allocator.free(manifest_content);

    const manifest = try std.json.parseFromSlice(std.json.Value, allocator, manifest_content, .{});
    defer manifest.deinit();
    if (manifest.value != .object) return error.InvalidTraceManifest;
    const manifest_object = manifest.value.object;

    const scenario_name = stringField(manifest_object, "scenarioName") orelse "";
    const status = stringField(manifest_object, "status") orelse "";
    const app_id = stringField(manifest_object, "appId");
    const error_name = stringField(manifest_object, "error");
    const failed_step_index = intField(manifest_object, "failedStepIndex");
    const duration_ms = intField(manifest_object, "durationMs");
    const event_count = intField(manifest_object, "eventCount");
    const snapshot_count = intField(manifest_object, "snapshotCount");

    const events_path = try std.fs.path.join(allocator, &.{ trace_dir, stringField(manifest_object, "eventsPath") orelse "events.jsonl" });
    defer allocator.free(events_path);
    const events_content = try std.fs.cwd().readFileAlloc(allocator, events_path, 64 * 1024 * 1024);
    defer allocator.free(events_content);

    var terminal = TerminalEvent{};
    defer terminal.deinit(allocator);
    var diagnostic = DiagnosticEvent{};
    defer diagnostic.deinit(allocator);
    var last_kind: ?[]u8 = null;
    defer if (last_kind) |value| allocator.free(value);

    var lines = std.mem.splitScalar(u8, events_content, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r\n");
        if (line.len == 0) continue;

        const parsed = std.json.parseFromSlice(std.json.Value, allocator, line, .{}) catch continue;
        defer parsed.deinit();
        if (parsed.value != .object) continue;
        const object = parsed.value.object;
        const kind = stringField(object, "kind") orelse continue;
        if (last_kind) |old| allocator.free(old);
        last_kind = try allocator.dupe(u8, kind);

        const payload_value = object.get("payload") orelse continue;
        if (payload_value != .object) continue;
        const payload = payload_value.object;

        if (std.mem.eql(u8, kind, "scenario.end")) {
            try terminal.setStatus(allocator, stringField(payload, "status"));
            try terminal.setErrorName(allocator, stringField(payload, "error"));
            terminal.failed_step_index = intField(payload, "failedStepIndex");
        } else if (isDiagnosticKind(kind, payload)) {
            try diagnostic.replace(allocator, kind, payload);
        }
    }

    return .{
        .scenario_name = try allocator.dupe(u8, scenario_name),
        .status = try allocator.dupe(u8, terminal.status orelse status),
        .app_id = try dupeOptionalString(allocator, app_id),
        .duration_ms = duration_ms,
        .event_count = event_count,
        .snapshot_count = snapshot_count,
        .failed_step_index = terminal.failed_step_index orelse failed_step_index,
        .error_name = try dupeOptionalString(allocator, terminal.error_name orelse error_name),
        .diagnostic = blk: {
            const value = diagnostic;
            diagnostic = .{};
            break :blk value;
        },
        .last_kind = blk: {
            const value = last_kind;
            last_kind = null;
            break :blk value;
        },
    };
}

fn writeTraceExplanationText(writer: anytype, explanation: TraceExplanation) !void {
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

fn writeTraceExplanationJsonValue(writer: anytype, explanation: TraceExplanation) !void {
    try writer.writeAll("{\"ok\":true,\"scenario\":");
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
        try writeDiagnosticJson(writer, explanation.diagnostic);
    }
    if (explanation.last_kind) |value| {
        try writer.writeAll(",\"lastEvent\":");
        try trace.writeJsonString(writer, value);
    }
    try writer.writeAll("}\n");
}

fn writeDiagnosticJson(writer: anytype, diagnostic: DiagnosticEvent) !void {
    try writer.writeAll("{\"kind\":");
    try trace.writeJsonString(writer, diagnostic.kind.?);
    if (diagnostic.status) |value| {
        try writer.writeAll(",\"status\":");
        try trace.writeJsonString(writer, value);
    }
    if (diagnostic.snapshot_id) |value| {
        try writer.writeAll(",\"snapshotId\":");
        try trace.writeJsonString(writer, value);
    }
    if (diagnostic.active_package) |value| {
        try writer.writeAll(",\"activePackage\":");
        try trace.writeJsonString(writer, value);
    }
    if (diagnostic.active_activity) |value| {
        try writer.writeAll(",\"activeActivity\":");
        try trace.writeJsonString(writer, value);
    }
    if (diagnostic.visible_texts) |value| {
        try writer.writeAll(",\"visibleTexts\":");
        try writeJoinedStringArrayJson(writer, value);
    }
    if (diagnostic.nearest_matches) |value| {
        try writer.writeAll(",\"nearestTextMatches\":");
        try writeJoinedStringArrayJson(writer, value);
    }
    try writer.writeAll("}");
}

fn writeJoinedStringArrayJson(writer: anytype, value: []const u8) !void {
    try writer.writeAll("[");
    var first = true;
    var parts = std.mem.splitSequence(u8, value, " | ");
    while (parts.next()) |part| {
        if (!first) try writer.writeAll(",");
        first = false;
        try trace.writeJsonString(writer, part);
    }
    try writer.writeAll("]");
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

        const tool = stringField(object, "tool") orelse "";
        const status = stringField(object, "status") orelse "";
        const trace_status = stringField(object, "traceStatus") orelse "";
        const trace_error = stringField(object, "traceError") orelse "";
        const trace_dir = stringField(object, "traceDir") orelse "";
        const run = intField(object, "run") orelse 0;
        const duration_ms = intField(object, "durationMs") orelse 0;
        const failed_step = intField(object, "failedStepIndex");

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
        try htmlEscape(writer, tool);
        try writer.writeAll("</td><td class=\"");
        try writer.writeAll(if (row_passed) "ok" else "failed");
        try writer.writeAll("\">");
        try htmlEscape(writer, status);
        try writer.writeAll("</td><td>");
        try writer.print("{d}", .{duration_ms});
        try writer.writeAll("</td><td>");
        try htmlEscape(writer, trace_status);
        try writer.writeAll("</td><td>");
        if (failed_step) |index| {
            try writer.print("failedStepIndex={d}", .{index});
        }
        if (trace_error.len > 0) {
            if (failed_step != null) try writer.writeAll(" ");
            try htmlEscape(writer, trace_error);
        }
        try writer.writeAll("</td><td>");
        if (trace_dir.len > 0) {
            const events_path = try std.fs.path.join(allocator, &.{ trace_dir, "events.jsonl" });
            defer allocator.free(events_path);
            try writeArtifactLink(allocator, writer, events_path, "events.jsonl");
        }
        try writer.writeAll("</td></tr>\n");
    }

    std.mem.sort(i64, durations.items, {}, std.sort.asc(i64));
    const mean = meanDuration(durations.items);
    const p95 = percentile95(durations.items);

    var html = std.ArrayList(u8).empty;
    defer html.deinit(allocator);
    const writer = html.writer(allocator);
    try writeHtmlStart(writer, "ZMR Report");
    try writer.writeAll("<h1>ZMR Report</h1>\n");
    try writer.writeAll("<p class=\"muted\">Source: ");
    try htmlEscape(writer, input_path);
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
    try writeHtmlEnd(writer);
    try writeFile(out_path, html.items);
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
        const seq = intField(object, "seq") orelse @as(i64, @intCast(total + 1));
        const kind = stringField(object, "kind") orelse "";
        if (std.mem.eql(u8, kind, "scenario.end")) {
            if (object.get("payload")) |payload| {
                if (payload == .object) {
                    if (stringField(payload.object, "status")) |value| {
                        if (terminal_status) |old| allocator.free(old);
                        terminal_status = try allocator.dupe(u8, value);
                    }
                    if (stringField(payload.object, "error")) |value| {
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
        try htmlEscape(writer, kind);
        try writer.writeAll("</td><td><code>");
        try htmlEscape(writer, line);
        try writer.writeAll("</code></td></tr>\n");
    }

    var html = std.ArrayList(u8).empty;
    defer html.deinit(allocator);
    const writer = html.writer(allocator);
    try writeHtmlStart(writer, "ZMR Trace Report");
    try writer.writeAll("<h1>ZMR Trace Report</h1>\n");
    try writer.writeAll("<p class=\"muted\">Source: ");
    try htmlEscape(writer, input_path);
    try writer.writeAll("</p>\n");
    try writer.writeAll("<section><h2>Trace Summary</h2><dl>");
    try writer.print("<dt>Events</dt><dd>{d}</dd>", .{total});
    try writer.writeAll("<dt>Terminal Status</dt><dd>");
    try htmlEscape(writer, terminal_status orelse "");
    try writer.writeAll("</dd><dt>Error</dt><dd>");
    try htmlEscape(writer, terminal_error orelse "");
    try writer.writeAll("</dd></dl></section>\n");
    try writer.writeAll("<section><h2>Timeline</h2><table><thead><tr><th>Seq</th><th>Kind</th><th>Event</th></tr></thead><tbody>\n");
    try writer.writeAll(events_html.items);
    try writer.writeAll("</tbody></table></section>\n");
    try writer.writeAll("<p>");
    try writeArtifactLink(allocator, writer, events_path, "events.jsonl");
    try writer.writeAll("</p>\n");
    try writer.writeAll("<p class=\"warning\">Screenshots and raw UI XML may contain app data. Sanitize trace bundles before public sharing.</p>\n");
    try writeHtmlEnd(writer);
    try writeFile(out_path, html.items);

    const relative_report_path = std.fs.path.relative(allocator, input_path, out_path) catch try allocator.dupe(u8, out_path);
    defer allocator.free(relative_report_path);
    try trace.attachReportPath(allocator, input_path, relative_report_path);
}

fn writeHtmlStart(writer: anytype, title: []const u8) !void {
    try writer.writeAll("<!doctype html><html><head><meta charset=\"utf-8\"><title>");
    try htmlEscape(writer, title);
    try writer.writeAll(
        \\</title><style>
        \\body{font-family:system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;margin:32px;color:#17202a;background:#f7f8fa}
        \\h1,h2{color:#111827}
        \\section{margin:24px 0}
        \\dl{display:grid;grid-template-columns:max-content 1fr;gap:8px 16px}
        \\dt{font-weight:700}
        \\table{border-collapse:collapse;width:100%;background:#fff}
        \\th,td{border:1px solid #d8dee6;padding:8px;text-align:left;vertical-align:top}
        \\th{background:#eef2f7}
        \\.ok{color:#116329;font-weight:700}
        \\.failed{color:#b42318;font-weight:700}
        \\.muted{color:#667085}
        \\.warning{border-left:4px solid #b54708;background:#fff7ed;padding:12px}
        \\code{white-space:pre-wrap;word-break:break-word}
        \\</style></head><body>
        \\
    );
}

fn writeHtmlEnd(writer: anytype) !void {
    try writer.writeAll("</body></html>\n");
}

fn writeFile(path: []const u8, bytes: []const u8) !void {
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(bytes);
}

fn writeArtifactLink(
    allocator: std.mem.Allocator,
    writer: anytype,
    path: []const u8,
    label: []const u8,
) !void {
    const href = std.fs.cwd().realpathAlloc(allocator, path) catch try allocator.dupe(u8, path);
    defer allocator.free(href);

    try writer.writeAll("<a href=\"file://");
    try htmlEscape(writer, href);
    try writer.writeAll("\">");
    try htmlEscape(writer, label);
    try writer.writeAll("</a>");
}

fn htmlEscape(writer: anytype, value: []const u8) !void {
    for (value) |ch| {
        switch (ch) {
            '&' => try writer.writeAll("&amp;"),
            '<' => try writer.writeAll("&lt;"),
            '>' => try writer.writeAll("&gt;"),
            '"' => try writer.writeAll("&quot;"),
            '\'' => try writer.writeAll("&#39;"),
            else => try writer.writeByte(ch),
        }
    }
}

fn stringField(object: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const value = object.get(key) orelse return null;
    if (value != .string) return null;
    return value.string;
}

fn intField(object: std.json.ObjectMap, key: []const u8) ?i64 {
    const value = object.get(key) orelse return null;
    return switch (value) {
        .integer => |actual| actual,
        else => null,
    };
}

const TerminalEvent = struct {
    status: ?[]u8 = null,
    error_name: ?[]u8 = null,
    failed_step_index: ?i64 = null,

    fn deinit(self: *TerminalEvent, allocator: std.mem.Allocator) void {
        if (self.status) |value| allocator.free(value);
        if (self.error_name) |value| allocator.free(value);
    }

    fn setStatus(self: *TerminalEvent, allocator: std.mem.Allocator, value: ?[]const u8) !void {
        if (self.status) |old| allocator.free(old);
        self.status = if (value) |actual| try allocator.dupe(u8, actual) else null;
    }

    fn setErrorName(self: *TerminalEvent, allocator: std.mem.Allocator, value: ?[]const u8) !void {
        if (self.error_name) |old| allocator.free(old);
        self.error_name = if (value) |actual| try allocator.dupe(u8, actual) else null;
    }
};

const DiagnosticEvent = struct {
    kind: ?[]u8 = null,
    status: ?[]u8 = null,
    snapshot_id: ?[]u8 = null,
    active_package: ?[]u8 = null,
    active_activity: ?[]u8 = null,
    visible_texts: ?[]u8 = null,
    nearest_matches: ?[]u8 = null,

    fn deinit(self: *DiagnosticEvent, allocator: std.mem.Allocator) void {
        if (self.kind) |value| allocator.free(value);
        if (self.status) |value| allocator.free(value);
        if (self.snapshot_id) |value| allocator.free(value);
        if (self.active_package) |value| allocator.free(value);
        if (self.active_activity) |value| allocator.free(value);
        if (self.visible_texts) |value| allocator.free(value);
        if (self.nearest_matches) |value| allocator.free(value);
    }

    fn replace(self: *DiagnosticEvent, allocator: std.mem.Allocator, kind_value: []const u8, payload: std.json.ObjectMap) !void {
        self.deinit(allocator);
        self.* = .{};
        self.kind = try allocator.dupe(u8, kind_value);
        self.status = try dupeOptionalString(allocator, stringField(payload, "status"));
        self.snapshot_id = try dupeOptionalString(allocator, stringField(payload, "snapshotId"));
        self.active_package = try dupeOptionalString(allocator, stringField(payload, "activePackage"));
        self.active_activity = try dupeOptionalString(allocator, stringField(payload, "activeActivity"));
        if (payload.get("visibleTexts")) |value| self.visible_texts = try joinStringArray(allocator, value, 8);
        if (payload.get("nearestTextMatches")) |value| self.nearest_matches = try joinNearestMatches(allocator, value, 5);
    }
};

fn dupeOptionalString(allocator: std.mem.Allocator, value: ?[]const u8) !?[]u8 {
    if (value) |actual| return try allocator.dupe(u8, actual);
    return null;
}

fn isDiagnosticKind(kind: []const u8, payload: std.json.ObjectMap) bool {
    if (payload.get("snapshotId") == null) return false;
    return std.mem.indexOf(u8, kind, "wait.") != null or
        std.mem.indexOf(u8, kind, "notFound") != null or
        std.mem.indexOf(u8, kind, "scrollUntilVisible") != null;
}

fn joinStringArray(allocator: std.mem.Allocator, value: std.json.Value, limit: usize) !?[]u8 {
    if (value != .array or value.array.items.len == 0) return null;
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    var written: usize = 0;
    for (value.array.items) |item| {
        if (item != .string) continue;
        if (written > 0) try out.writer(allocator).writeAll(" | ");
        try out.writer(allocator).writeAll(item.string);
        written += 1;
        if (written >= limit) break;
    }
    if (written == 0) {
        out.deinit(allocator);
        return null;
    }
    return try out.toOwnedSlice(allocator);
}

fn joinNearestMatches(allocator: std.mem.Allocator, value: std.json.Value, limit: usize) !?[]u8 {
    if (value != .array or value.array.items.len == 0) return null;
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    var written: usize = 0;
    for (value.array.items) |item| {
        if (item != .object) continue;
        const text = stringField(item.object, "text") orelse continue;
        if (written > 0) try out.writer(allocator).writeAll(" | ");
        try out.writer(allocator).writeAll(text);
        if (intField(item.object, "score")) |score| {
            try out.writer(allocator).print(" (score {d})", .{score});
        }
        written += 1;
        if (written >= limit) break;
    }
    if (written == 0) {
        out.deinit(allocator);
        return null;
    }
    return try out.toOwnedSlice(allocator);
}

fn meanDuration(durations: []const i64) i64 {
    if (durations.len == 0) return 0;
    var total: i64 = 0;
    for (durations) |duration| total += duration;
    return @divTrunc(total, @as(i64, @intCast(durations.len)));
}

fn percentile95(durations: []const i64) i64 {
    if (durations.len == 0) return 0;
    return durations[@as(usize, @intFromFloat(@floor(@as(f64, @floatFromInt(durations.len - 1)) * 0.95)))];
}

test "report writes benchmark html with terminal trace fields" {
    const allocator = std.testing.allocator;
    const root = "zig-cache-test-report-benchmark";
    const out_path = root ++ "/report.html";
    const trace_dir = root ++ "/zmr-2";
    defer std.fs.cwd().deleteTree(root) catch {};
    try std.fs.cwd().makePath(trace_dir);

    {
        var results = try std.fs.cwd().createFile(root ++ "/results.jsonl", .{ .truncate = true });
        defer results.close();
        try results.writeAll(
            "{\"tool\":\"zmr\",\"run\":1,\"status\":\"ok\",\"durationMs\":1000,\"traceDir\":\"" ++ root ++ "/zmr-1\",\"traceStatus\":\"passed\"}\n" ++
                "{\"tool\":\"zmr\",\"run\":2,\"status\":\"failed\",\"durationMs\":2000,\"traceDir\":\"" ++ trace_dir ++ "\",\"traceStatus\":\"failed\",\"traceError\":\"WaitTimeout\",\"failedStepIndex\":5}\n",
        );
    }
    {
        var events = try std.fs.cwd().createFile(trace_dir ++ "/events.jsonl", .{ .truncate = true });
        defer events.close();
        try events.writeAll(
            "{\"seq\":1,\"kind\":\"step.error\",\"payload\":{\"index\":5,\"error\":\"WaitTimeout\"}}\n" ++
                "{\"seq\":2,\"kind\":\"scenario.end\",\"payload\":{\"value\":\"flow\",\"status\":\"failed\",\"failedStepIndex\":5,\"error\":\"WaitTimeout\"}}\n",
        );
    }

    try writeHtmlReport(allocator, root, out_path);

    const html = try std.fs.cwd().readFileAlloc(allocator, out_path, 1024 * 1024);
    defer allocator.free(html);
    try std.testing.expect(std.mem.indexOf(u8, html, "ZMR Report") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "Pass Rate") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "1/2") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "WaitTimeout") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "failedStepIndex") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "events.jsonl") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "file://") != null);
}

test "report writes single trace html with terminal event" {
    const allocator = std.testing.allocator;
    const root = "zig-cache-test-report-trace";
    const out_path = root ++ "/report.html";
    defer std.fs.cwd().deleteTree(root) catch {};
    try std.fs.cwd().makePath(root);

    {
        var events = try std.fs.cwd().createFile(root ++ "/events.jsonl", .{ .truncate = true });
        defer events.close();
        try events.writeAll(
            "{\"seq\":1,\"kind\":\"wait.visible\",\"payload\":{\"status\":\"ok\"}}\n" ++
                "{\"seq\":2,\"kind\":\"scenario.end\",\"payload\":{\"value\":\"flow\",\"status\":\"passed\"}}\n",
        );
    }
    {
        var manifest = try std.fs.cwd().createFile(root ++ "/trace.json", .{ .truncate = true });
        defer manifest.close();
        try manifest.writeAll(
            "{\"schemaVersion\":1,\"runnerVersion\":\"0.1.0-dev\",\"protocolVersion\":\"2026-04-28\",\"scenarioName\":\"flow\",\"appId\":\"com.example.mobiletest\",\"status\":\"passed\",\"startedAtMs\":1,\"endedAtMs\":2,\"durationMs\":1,\"failedStepIndex\":null,\"error\":null,\"eventsPath\":\"events.jsonl\",\"artifactsDir\":\"artifacts\",\"eventCount\":2,\"snapshotCount\":0,\"reportPath\":null}\n",
        );
    }

    try writeHtmlReport(allocator, root, out_path);

    const html = try std.fs.cwd().readFileAlloc(allocator, out_path, 1024 * 1024);
    defer allocator.free(html);
    try std.testing.expect(std.mem.indexOf(u8, html, "ZMR Trace Report") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "Terminal Status") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "passed") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "scenario.end") != null);
    try std.testing.expect(std.mem.indexOf(u8, html, "file://") != null);

    const manifest = try std.fs.cwd().readFileAlloc(allocator, root ++ "/trace.json", 1024 * 1024);
    defer allocator.free(manifest);
    const parsed_manifest = try std.json.parseFromSlice(std.json.Value, allocator, manifest, .{});
    defer parsed_manifest.deinit();
    try std.testing.expectEqualStrings("report.html", parsed_manifest.value.object.get("reportPath").?.string);
}

test "trace explanation summarizes terminal failure diagnostics" {
    const allocator = std.testing.allocator;
    const root = "zig-cache-test-explain-trace";
    defer std.fs.cwd().deleteTree(root) catch {};
    try std.fs.cwd().makePath(root);

    {
        var manifest = try std.fs.cwd().createFile(root ++ "/trace.json", .{ .truncate = true });
        defer manifest.close();
        try manifest.writeAll(
            "{\"schemaVersion\":1,\"runnerVersion\":\"0.1.0-dev\",\"protocolVersion\":\"2026-04-28\",\"scenarioName\":\"login smoke\",\"appId\":\"com.example.mobiletest\",\"status\":\"failed\",\"startedAtMs\":1,\"endedAtMs\":101,\"durationMs\":100,\"failedStepIndex\":2,\"error\":\"WaitTimeout\",\"eventsPath\":\"events.jsonl\",\"artifactsDir\":\"artifacts\",\"eventCount\":4,\"snapshotCount\":1,\"reportPath\":null}\n",
        );
    }
    {
        var events = try std.fs.cwd().createFile(root ++ "/events.jsonl", .{ .truncate = true });
        defer events.close();
        try events.writeAll(
            "{\"seq\":1,\"kind\":\"scenario.start\",\"payload\":{\"value\":\"login smoke\"}}\n" ++
                "{\"seq\":2,\"kind\":\"wait.visible\",\"payload\":{\"status\":\"timeout\",\"snapshotId\":\"snapshot-7\",\"selectors\":[{\"text\":\"Dashboard\"}],\"activePackage\":\"com.example.mobiletest\",\"activeActivity\":\".MainActivity\",\"visibleTexts\":[\"Sign in\",\"Try again\"],\"nearestTextMatches\":[{\"stableId\":\"title\",\"text\":\"Dashboards\",\"score\":1,\"enabled\":true,\"visible\":true}]}}\n" ++
                "{\"seq\":3,\"kind\":\"step.error\",\"payload\":{\"index\":2,\"error\":\"WaitTimeout\"}}\n" ++
                "{\"seq\":4,\"kind\":\"scenario.end\",\"payload\":{\"value\":\"login smoke\",\"status\":\"failed\",\"failedStepIndex\":2,\"error\":\"WaitTimeout\"}}\n",
        );
    }

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    try writeTraceExplanation(allocator, root, out.writer(allocator));

    try std.testing.expect(std.mem.indexOf(u8, out.items, "scenario: login smoke") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "status: failed") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "failedStepIndex: 2") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "error: WaitTimeout") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "diagnostic: wait.visible timeout") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "snapshot: snapshot-7") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "visibleTexts: Sign in | Try again") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "nearestTextMatches: Dashboards") != null);
}
