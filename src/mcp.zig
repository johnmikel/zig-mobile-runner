const std = @import("std");
const bundle = @import("bundle.zig");
const errors = @import("errors.zig");
const runner = @import("runner.zig");
const selector = @import("selector.zig");
const semantic = @import("semantic.zig");
const trace = @import("trace.zig");
const version = @import("version.zig");

pub fn serveStdioWithTrace(allocator: std.mem.Allocator, device: anytype, live_trace: ?*trace.TraceWriter) !void {
    var stdin = std.fs.File.stdin().deprecatedReader();
    const stdout = std.fs.File.stdout().deprecatedWriter();

    while (true) {
        const line = stdin.readUntilDelimiterOrEofAlloc(allocator, '\n', 16 * 1024 * 1024) catch |err| {
            try writeError(stdout, null, -32700, @errorName(err));
            continue;
        };
        const owned_line = line orelse break;
        defer allocator.free(owned_line);
        const trimmed = std.mem.trim(u8, owned_line, " \t\r\n");
        if (trimmed.len == 0) continue;
        try dispatchLine(allocator, device, trimmed, stdout, live_trace);
    }
}

fn dispatchLine(
    allocator: std.mem.Allocator,
    device: anytype,
    line: []const u8,
    writer: anytype,
    live_trace: ?*trace.TraceWriter,
) !void {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, line, .{}) catch |err| {
        try writeError(writer, null, -32700, @errorName(err));
        return;
    };
    defer parsed.deinit();

    if (parsed.value != .object) {
        try writeError(writer, null, -32600, "request must be an object");
        return;
    }
    const object = parsed.value.object;
    const id = object.get("id");
    const method_value = object.get("method") orelse {
        try writeError(writer, id, -32600, "missing method");
        return;
    };
    if (method_value != .string) {
        try writeError(writer, id, -32600, "method must be a string");
        return;
    }

    dispatchMethod(allocator, device, method_value.string, object.get("params"), id, writer, live_trace) catch |err| {
        const classified = errors.classify(err);
        try writeErrorWithPublicCode(writer, id, -32000, @errorName(err), classified.code);
        return;
    };
}

fn dispatchMethod(
    allocator: std.mem.Allocator,
    device: anytype,
    method: []const u8,
    params: ?std.json.Value,
    id: ?std.json.Value,
    writer: anytype,
    live_trace: ?*trace.TraceWriter,
) !void {
    if (std.mem.eql(u8, method, "initialize")) {
        const protocol_version = optionalParamString(params, "protocolVersion") orelse "2024-11-05";
        try writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
        try writeId(writer, id);
        try writer.writeAll(",\"result\":{\"protocolVersion\":");
        try trace.writeJsonString(writer, protocol_version);
        try writer.writeAll(",\"capabilities\":{\"tools\":{}},\"serverInfo\":{\"name\":\"zmr\",\"version\":");
        try trace.writeJsonString(writer, version.runner_version);
        try writer.writeAll("}}}\n");
        return;
    }

    if (std.mem.eql(u8, method, "ping")) {
        try writeResultRaw(writer, id, "{}");
        return;
    }

    if (std.mem.eql(u8, method, "tools/list")) {
        try writeResultRaw(writer, id, "{\"tools\":[{\"name\":\"snapshot\",\"description\":\"Capture the current mobile observation snapshot as JSON.\",\"inputSchema\":{\"type\":\"object\",\"additionalProperties\":false,\"properties\":{}}},{\"name\":\"semantic_snapshot\",\"description\":\"Capture an agent-optimized mobile semantic tree with roles, names, selectors, bounds, and recommended actions.\",\"inputSchema\":{\"type\":\"object\",\"additionalProperties\":false,\"properties\":{}}},{\"name\":\"tap\",\"description\":\"Tap a visible element by selector.\",\"inputSchema\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"selector\"],\"properties\":{\"selector\":{\"type\":\"object\"}}}},{\"name\":\"type\",\"description\":\"Type text, optionally after focusing an element by selector.\",\"inputSchema\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"text\"],\"properties\":{\"selector\":{\"type\":\"object\"},\"text\":{\"type\":\"string\"}}}},{\"name\":\"press_back\",\"description\":\"Press Android back or the platform-equivalent navigation action.\",\"inputSchema\":{\"type\":\"object\",\"additionalProperties\":false,\"properties\":{}}},{\"name\":\"open_link\",\"description\":\"Open a deep link URL in the target app.\",\"inputSchema\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"url\"],\"properties\":{\"url\":{\"type\":\"string\"}}}},{\"name\":\"wait_visible\",\"description\":\"Wait for an element selector to become visible.\",\"inputSchema\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"selector\"],\"properties\":{\"selector\":{\"type\":\"object\"},\"timeoutMs\":{\"type\":\"integer\",\"minimum\":0}}}},{\"name\":\"trace_events\",\"description\":\"Read live trace events from a traced MCP session.\",\"inputSchema\":{\"type\":\"object\",\"additionalProperties\":false,\"properties\":{\"afterSeq\":{\"type\":\"integer\",\"minimum\":0},\"limit\":{\"type\":\"integer\",\"minimum\":1}}}},{\"name\":\"trace_export\",\"description\":\"Export the active trace directory as a .zmrtrace bundle.\",\"inputSchema\":{\"type\":\"object\",\"additionalProperties\":false,\"required\":[\"out\"],\"properties\":{\"out\":{\"type\":\"string\"},\"redact\":{\"type\":\"boolean\"},\"omitScreenshots\":{\"type\":\"boolean\"}}}}]}");
        return;
    }

    if (std.mem.eql(u8, method, "tools/call")) {
        const tool_name = try requiredParamString(params, "name");
        const arguments = paramField(params, "arguments");
        try callTool(allocator, device, tool_name, arguments, id, writer, live_trace);
        return;
    }

    try writeError(writer, id, -32601, "method not found");
}

fn callTool(
    allocator: std.mem.Allocator,
    device: anytype,
    tool_name: []const u8,
    arguments: ?std.json.Value,
    id: ?std.json.Value,
    writer: anytype,
    live_trace: ?*trace.TraceWriter,
) !void {
    if (std.mem.eql(u8, tool_name, "snapshot")) {
        var snap = try device.snapshot(live_trace);
        defer snap.deinit(device.allocator);
        var payload = std.ArrayList(u8).empty;
        defer payload.deinit(allocator);
        try trace.writeSnapshotJson(payload.writer(allocator), snap);
        try writeToolTextResult(writer, id, payload.items);
        return;
    }

    if (std.mem.eql(u8, tool_name, "semantic_snapshot")) {
        var snap = try device.snapshot(live_trace);
        defer snap.deinit(device.allocator);
        if (live_trace) |tw| {
            const path = try tw.writeSnapshot(snap);
            defer tw.allocator.free(path);
            try tw.recordEvent("observe.semanticSnapshot", "{\"status\":\"ok\"}");
        }
        var payload = std.ArrayList(u8).empty;
        defer payload.deinit(allocator);
        try semantic.writeSemanticSnapshotJson(payload.writer(allocator), snap);
        try writeToolTextResult(writer, id, payload.items);
        return;
    }

    if (std.mem.eql(u8, tool_name, "tap")) {
        const wanted = try parseArgumentsSelector(allocator, arguments);
        defer wanted.deinit(allocator);
        try runner.tapSelector(device, wanted, live_trace, .{});
        try writeToolTextResult(writer, id, "{\"ok\":true}");
        return;
    }

    if (std.mem.eql(u8, tool_name, "type")) {
        const text = try requiredParamString(arguments, "text");
        if (paramField(arguments, "selector")) |selector_value| {
            const wanted = try selector.parseFromJson(allocator, selector_value);
            defer wanted.deinit(allocator);
            try runner.typeTextSelector(device, wanted, text, live_trace, .{});
        } else {
            try device.typeText(text);
        }
        try writeToolTextResult(writer, id, "{\"ok\":true}");
        return;
    }

    if (std.mem.eql(u8, tool_name, "press_back")) {
        try device.pressBack();
        try writeToolTextResult(writer, id, "{\"ok\":true}");
        return;
    }

    if (std.mem.eql(u8, tool_name, "open_link")) {
        try device.openLink(try requiredParamString(arguments, "url"));
        try writeToolTextResult(writer, id, "{\"ok\":true}");
        return;
    }

    if (std.mem.eql(u8, tool_name, "wait_visible")) {
        const wanted = try parseArgumentsSelector(allocator, arguments);
        defer wanted.deinit(allocator);
        const timeout_ms = try optionalParamU64(arguments, "timeoutMs", 5000);
        const visible = try runner.waitUntilVisible(device, wanted, timeout_ms, live_trace, .{});
        try writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
        try writeId(writer, id);
        try writer.writeAll(",\"result\":{\"content\":[{\"type\":\"text\",\"text\":\"{\\\"visible\\\":");
        try writer.writeAll(if (visible) "true" else "false");
        try writer.writeAll("}\"}]}}\n");
        return;
    }

    if (std.mem.eql(u8, tool_name, "trace_events")) {
        try writeTraceEventsToolResult(allocator, writer, id, live_trace, try optionalParamU64(arguments, "afterSeq", 0), @min(try optionalParamU64(arguments, "limit", 100), 1000));
        return;
    }

    if (std.mem.eql(u8, tool_name, "trace_export")) {
        const tw = live_trace orelse {
            try writeToolTextResult(writer, id, "{\"traceDir\":null,\"message\":\"start zmr mcp with --trace-dir to enable export\"}");
            return;
        };
        const out_path = try requiredParamString(arguments, "out");
        const omit_screenshots = try optionalParamBool(arguments, "omitScreenshots", false);
        const redact = try optionalParamBool(arguments, "redact", false) or omit_screenshots;
        try tw.flushManifest();
        try bundle.exportTraceBundleWithOptions(allocator, tw.root_dir, out_path, .{
            .redact = redact,
            .omit_screenshots = omit_screenshots,
        });
        var payload = std.ArrayList(u8).empty;
        defer payload.deinit(allocator);
        const payload_writer = payload.writer(allocator);
        try payload_writer.writeAll("{\"traceDir\":");
        try trace.writeJsonString(payload_writer, tw.root_dir);
        try payload_writer.writeAll(",\"out\":");
        try trace.writeJsonString(payload_writer, out_path);
        try payload_writer.print(",\"redacted\":{},\"omitScreenshots\":{}}}", .{ redact, omit_screenshots });
        try writeToolTextResult(writer, id, payload.items);
        return;
    }

    try writeError(writer, id, -32602, "unknown tool");
}

fn parseArgumentsSelector(allocator: std.mem.Allocator, arguments: ?std.json.Value) !selector.Selector {
    const selector_value = paramField(arguments, "selector") orelse return error.MissingSelector;
    return try selector.parseFromJson(allocator, selector_value);
}

fn writeTraceEventsToolResult(
    allocator: std.mem.Allocator,
    writer: anytype,
    id: ?std.json.Value,
    live_trace: ?*trace.TraceWriter,
    after_seq: u64,
    limit: u64,
) !void {
    const tw = live_trace orelse {
        try writeToolTextResult(writer, id, "{\"traceDir\":null,\"events\":[]}");
        return;
    };

    const events_path = try std.fs.path.join(allocator, &.{ tw.root_dir, "events.jsonl" });
    defer allocator.free(events_path);
    const content = std.fs.cwd().readFileAlloc(allocator, events_path, 64 * 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => try allocator.dupe(u8, ""),
        else => return err,
    };
    defer allocator.free(content);

    var payload = std.ArrayList(u8).empty;
    defer payload.deinit(allocator);
    const payload_writer = payload.writer(allocator);
    try payload_writer.writeAll("{\"traceDir\":");
    try trace.writeJsonString(payload_writer, tw.root_dir);
    try payload_writer.print(",\"afterSeq\":{d},\"events\":[", .{after_seq});
    var emitted: u64 = 0;
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |raw_line| {
        if (emitted >= limit) break;
        const line = std.mem.trim(u8, raw_line, " \t\r\n");
        if (line.len == 0) continue;
        const parsed = std.json.parseFromSlice(std.json.Value, allocator, line, .{}) catch continue;
        defer parsed.deinit();
        if (parsed.value != .object) continue;
        const seq_value = parsed.value.object.get("seq") orelse continue;
        if (seq_value != .integer or seq_value.integer <= 0) continue;
        const seq = @as(u64, @intCast(seq_value.integer));
        if (seq <= after_seq) continue;
        if (emitted > 0) try payload_writer.writeAll(",");
        try payload_writer.writeAll(line);
        emitted += 1;
    }
    try payload_writer.writeAll("]}");
    try writeToolTextResult(writer, id, payload.items);
}

fn writeToolTextResult(writer: anytype, id: ?std.json.Value, text: []const u8) !void {
    try writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
    try writeId(writer, id);
    try writer.writeAll(",\"result\":{\"content\":[{\"type\":\"text\",\"text\":");
    try trace.writeJsonString(writer, text);
    try writer.writeAll("}]}}\n");
}

fn writeResultRaw(writer: anytype, id: ?std.json.Value, raw_json: []const u8) !void {
    try writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
    try writeId(writer, id);
    try writer.writeAll(",\"result\":");
    try writer.writeAll(raw_json);
    try writer.writeAll("}\n");
}

fn writeError(writer: anytype, id: ?std.json.Value, code: i32, message: []const u8) !void {
    try writeErrorWithPublicCode(writer, id, code, message, null);
}

fn writeErrorWithPublicCode(writer: anytype, id: ?std.json.Value, code: i32, message: []const u8, public_code: ?[]const u8) !void {
    try writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
    try writeId(writer, id);
    try writer.print(",\"error\":{{\"code\":{d},\"message\":", .{code});
    try trace.writeJsonString(writer, message);
    if (public_code) |value| {
        try writer.writeAll(",\"publicCode\":");
        try trace.writeJsonString(writer, value);
    }
    try writer.writeAll("}}\n");
}

fn writeId(writer: anytype, id: ?std.json.Value) !void {
    const value = id orelse {
        try writer.writeAll("null");
        return;
    };
    switch (value) {
        .null => try writer.writeAll("null"),
        .string => |actual| try trace.writeJsonString(writer, actual),
        .integer => |actual| try writer.print("{d}", .{actual}),
        else => try writer.writeAll("null"),
    }
}

fn paramField(params: ?std.json.Value, key: []const u8) ?std.json.Value {
    const value = params orelse return null;
    if (value != .object) return null;
    return value.object.get(key);
}

fn requiredParamString(params: ?std.json.Value, key: []const u8) ![]const u8 {
    const value = paramField(params, key) orelse return error.MissingParam;
    return switch (value) {
        .string => |actual| actual,
        else => error.ParamMustBeString,
    };
}

fn optionalParamString(params: ?std.json.Value, key: []const u8) ?[]const u8 {
    const value = paramField(params, key) orelse return null;
    return switch (value) {
        .string => |actual| actual,
        else => null,
    };
}

fn optionalParamU64(params: ?std.json.Value, key: []const u8, default_value: u64) !u64 {
    const value = paramField(params, key) orelse return default_value;
    return switch (value) {
        .integer => |actual| @as(u64, @intCast(actual)),
        else => error.ParamMustBeInteger,
    };
}

fn optionalParamBool(params: ?std.json.Value, key: []const u8, default_value: bool) !bool {
    const value = paramField(params, key) orelse return default_value;
    return switch (value) {
        .bool => |actual| actual,
        else => error.ParamMustBeBool,
    };
}
