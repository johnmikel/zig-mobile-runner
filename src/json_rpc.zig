const std = @import("std");
const bundle = @import("bundle.zig");
const errors = @import("errors.zig");
const runner = @import("runner.zig");
const scenario = @import("scenario.zig");
const selector = @import("selector.zig");
const trace = @import("trace.zig");
const version = @import("version.zig");

pub const ServeOptions = struct {
    transport: []const u8 = "stdio",
};

pub fn serveStdio(allocator: std.mem.Allocator, device: anytype) !void {
    try serveStdioWithTrace(allocator, device, null);
}

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
        try dispatchLineWithTrace(allocator, device, trimmed, stdout, live_trace);
    }
}

pub fn serveTcp(allocator: std.mem.Allocator, device: anytype, port: u16) !void {
    try serveTcpWithTrace(allocator, device, port, null);
}

pub fn serveTcpWithTrace(allocator: std.mem.Allocator, device: anytype, port: u16, live_trace: ?*trace.TraceWriter) !void {
    const address = try std.net.Address.parseIp("127.0.0.1", port);
    var server = try address.listen(.{ .reuse_address = true });
    defer server.deinit();

    while (true) {
        var connection = try server.accept();
        defer connection.stream.close();
        try serveTcpConnection(allocator, device, connection.stream, live_trace);
    }
}

fn serveTcpConnection(allocator: std.mem.Allocator, device: anytype, stream: std.net.Stream, live_trace: ?*trace.TraceWriter) !void {
    var write_buffer: [8192]u8 = undefined;
    var stream_writer = stream.writer(&write_buffer);
    const writer = &stream_writer.interface;

    var line = std.ArrayList(u8).empty;
    defer line.deinit(allocator);

    var read_buffer: [4096]u8 = undefined;
    while (true) {
        const n = try stream.read(&read_buffer);
        if (n == 0) break;
        for (read_buffer[0..n]) |ch| {
            if (ch == '\n') {
                const trimmed = std.mem.trim(u8, line.items, " \t\r\n");
                if (trimmed.len != 0) {
                    try dispatchLineWithTrace(allocator, device, trimmed, writer, live_trace);
                    try writer.flush();
                }
                line.clearRetainingCapacity();
            } else {
                try line.append(allocator, ch);
            }
        }
    }

    if (line.items.len != 0) {
        const trimmed = std.mem.trim(u8, line.items, " \t\r\n");
        if (trimmed.len != 0) {
            try dispatchLineWithTrace(allocator, device, trimmed, writer, live_trace);
            try writer.flush();
        }
    }
}

fn dispatchLine(allocator: std.mem.Allocator, device: anytype, line: []const u8, writer: anytype) !void {
    try dispatchLineWithTrace(allocator, device, line, writer, null);
}

fn dispatchLineWithTrace(
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
    const params = object.get("params");

    if (live_trace) |tw| try recordRpcEvent(tw, "rpc.request", method_value.string, id);
    dispatchMethod(allocator, device, method_value.string, params, id, writer, live_trace) catch |err| {
        if (live_trace) |tw| try recordRpcErrorEvent(tw, method_value.string, id, err);
        const classified = errors.classify(err);
        try writeErrorWithPublicCode(writer, id, -32000, @errorName(err), classified.code);
        return;
    };
    if (live_trace) |tw| try recordRpcEvent(tw, "rpc.response", method_value.string, id);
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
    if (std.mem.eql(u8, method, "runner.capabilities")) {
        try writeResultRaw(writer, id, "{\"name\":\"zmr\",\"version\":\"" ++ version.runner_version ++ "\",\"protocolVersion\":\"" ++ version.protocol_version ++ "\",\"protocol\":{\"version\":\"" ++ version.protocol_version ++ "\",\"minimumCompatibleVersion\":\"" ++ version.protocol_min_compatible_version ++ "\",\"stability\":\"" ++ version.protocol_stability ++ "\",\"breakingChangePolicy\":\"" ++ version.protocol_breaking_change_policy ++ "\"},\"platforms\":[\"android\",\"ios\"],\"platformSupport\":{\"android\":{\"status\":\"supported\",\"deviceTypes\":[\"emulator\",\"physical\"],\"automation\":[\"adb\",\"uiautomator\",\"android-shim\"]},\"ios\":{\"status\":\"supported\",\"deviceTypes\":[\"simulator\"],\"automation\":[\"simctl\",\"xctest-shim\"],\"physicalDevices\":false}},\"iosPreview\":false,\"transports\":[\"stdio\",\"tcp\"],\"methods\":[\"runner.capabilities\",\"device.list\",\"session.create\",\"session.close\",\"app.install\",\"app.launch\",\"app.stop\",\"app.openLink\",\"app.clearState\",\"observe.snapshot\",\"ui.tap\",\"ui.type\",\"ui.eraseText\",\"ui.hideKeyboard\",\"ui.swipe\",\"ui.pressBack\",\"ui.scrollUntilVisible\",\"wait.until\",\"wait.any\",\"wait.gone\",\"assert.visible\",\"assert.notVisible\",\"trace.events\",\"trace.export\"]}");
        return;
    }
    if (std.mem.eql(u8, method, "device.list")) {
        const devices = try device.listDevices();
        defer {
            for (devices) |info| info.deinit(allocator);
            allocator.free(devices);
        }
        try writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
        try writeId(writer, id);
        try writer.writeAll(",\"result\":[");
        for (devices, 0..) |info, index| {
            if (index > 0) try writer.writeAll(",");
            try writer.writeAll("{\"serial\":");
            try trace.writeJsonString(writer, info.serial);
            try writer.writeAll(",\"state\":");
            try trace.writeJsonString(writer, info.state);
            try writer.writeAll("}");
        }
        try writer.writeAll("]}\n");
        return;
    }
    if (std.mem.eql(u8, method, "session.create")) {
        try writeResultRaw(writer, id, "{\"sessionId\":\"default\"}");
        return;
    }
    if (std.mem.eql(u8, method, "session.close")) {
        try writeResultRaw(writer, id, "true");
        return;
    }
    if (std.mem.eql(u8, method, "app.install")) {
        const path = try requiredParamString(params, "path");
        try device.install(path);
        try writeResultRaw(writer, id, "true");
        return;
    }
    if (std.mem.eql(u8, method, "app.launch")) {
        try device.launch();
        try writeResultRaw(writer, id, "true");
        return;
    }
    if (std.mem.eql(u8, method, "app.stop")) {
        try device.stop();
        try writeResultRaw(writer, id, "true");
        return;
    }
    if (std.mem.eql(u8, method, "app.clearState")) {
        try device.clearState();
        try writeResultRaw(writer, id, "true");
        return;
    }
    if (std.mem.eql(u8, method, "app.openLink")) {
        const url = try requiredParamString(params, "url");
        try device.openLink(url);
        try writeResultRaw(writer, id, "true");
        return;
    }
    if (std.mem.eql(u8, method, "observe.snapshot")) {
        var snap = try device.snapshot(live_trace);
        defer snap.deinit(device.allocator);
        if (live_trace) |tw| {
            const path = try tw.writeSnapshot(snap);
            defer tw.allocator.free(path);
            var payload = std.ArrayList(u8).empty;
            defer payload.deinit(tw.allocator);
            try payload.writer(tw.allocator).writeAll("{\"path\":");
            try trace.writeJsonString(payload.writer(tw.allocator), path);
            try payload.writer(tw.allocator).writeAll(",\"snapshotId\":");
            try trace.writeJsonString(payload.writer(tw.allocator), snap.id);
            try payload.writer(tw.allocator).writeAll("}");
            try tw.recordEvent("observe.snapshot", payload.items);
        }
        try writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
        try writeId(writer, id);
        try writer.writeAll(",\"result\":");
        try trace.writeSnapshotJson(writer, snap);
        try writer.writeAll("}\n");
        return;
    }
    if (std.mem.eql(u8, method, "ui.tap")) {
        const wanted = try parseParamSelector(allocator, params);
        defer wanted.deinit(allocator);
        try runner.tapSelector(device, wanted, live_trace, .{});
        try writeResultRaw(writer, id, "true");
        return;
    }
    if (std.mem.eql(u8, method, "ui.type")) {
        const text = try requiredParamString(params, "text");
        if (paramField(params, "selector")) |selector_value| {
            const wanted = try selector.parseFromJson(allocator, selector_value);
            defer wanted.deinit(allocator);
            try runner.typeTextSelector(device, wanted, text, live_trace, .{});
            try writeResultRaw(writer, id, "true");
            return;
        }
        try device.typeText(text);
        if (live_trace) |tw| try recordRpcSimplePayload(tw, "ui.type", "text", text);
        try writeResultRaw(writer, id, "true");
        return;
    }
    if (std.mem.eql(u8, method, "ui.eraseText")) {
        const max_chars = @as(u32, @intCast(try optionalParamU64(params, "maxChars", 80)));
        if (paramField(params, "selector")) |selector_value| {
            const wanted = try selector.parseFromJson(allocator, selector_value);
            defer wanted.deinit(allocator);
            try runner.eraseTextSelector(device, wanted, max_chars, live_trace, .{});
            try writeResultRaw(writer, id, "true");
            return;
        }
        try device.eraseText(max_chars);
        if (live_trace) |tw| {
            const payload = try std.fmt.allocPrint(tw.allocator, "{{\"maxChars\":{d}}}", .{max_chars});
            defer tw.allocator.free(payload);
            try tw.recordEvent("ui.eraseText", payload);
        }
        try writeResultRaw(writer, id, "true");
        return;
    }
    if (std.mem.eql(u8, method, "ui.hideKeyboard")) {
        try device.hideKeyboard();
        if (live_trace) |tw| try tw.recordEvent("ui.hideKeyboard", "{\"status\":\"ok\"}");
        try writeResultRaw(writer, id, "true");
        return;
    }
    if (std.mem.eql(u8, method, "ui.swipe")) {
        try device.swipe(
            try requiredParamI32(params, "x1"),
            try requiredParamI32(params, "y1"),
            try requiredParamI32(params, "x2"),
            try requiredParamI32(params, "y2"),
            @as(u32, @intCast(try optionalParamU64(params, "durationMs", 300))),
        );
        if (live_trace) |tw| try tw.recordEvent("ui.swipe", "{\"status\":\"ok\"}");
        try writeResultRaw(writer, id, "true");
        return;
    }
    if (std.mem.eql(u8, method, "ui.pressBack")) {
        try device.pressBack();
        if (live_trace) |tw| try tw.recordEvent("ui.pressBack", "{\"status\":\"ok\"}");
        try writeResultRaw(writer, id, "true");
        return;
    }
    if (std.mem.eql(u8, method, "ui.scrollUntilVisible")) {
        const wanted = try parseParamSelector(allocator, params);
        defer wanted.deinit(allocator);
        const ok = try runner.scrollUntilVisible(
            device,
            wanted,
            try optionalParamU64(params, "timeoutMs", 5000),
            try optionalParamDirection(params, "direction", .down),
            live_trace,
            .{},
        );
        try writeResultRaw(writer, id, if (ok) "true" else "false");
        return;
    }
    if (std.mem.eql(u8, method, "wait.until")) {
        const visible_value = paramField(params, "visible") orelse return error.WaitUntilNeedsVisibleSelector;
        const wanted = try selector.parseFromJson(allocator, visible_value);
        defer wanted.deinit(allocator);
        const timeout_ms = try optionalParamU64(params, "timeoutMs", 5000);
        const ok = try runner.waitUntilVisible(device, wanted, timeout_ms, live_trace, .{});
        try writeResultRaw(writer, id, if (ok) "true" else "false");
        return;
    }
    if (std.mem.eql(u8, method, "wait.any")) {
        const selectors = try parseParamSelectors(allocator, params);
        defer {
            for (selectors) |wanted| wanted.deinit(allocator);
            allocator.free(selectors);
        }
        const matched = try runner.waitUntilAnyVisible(device, selectors, try optionalParamU64(params, "timeoutMs", 5000), live_trace, .{});
        if (matched) |index| {
            try writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
            try writeId(writer, id);
            try writer.writeAll(",\"result\":{\"matchedIndex\":");
            try writer.print("{d}", .{index});
            try writer.writeAll("}}\n");
        } else {
            try writeResultRaw(writer, id, "false");
        }
        return;
    }
    if (std.mem.eql(u8, method, "wait.gone")) {
        const wanted = try parseParamSelector(allocator, params);
        defer wanted.deinit(allocator);
        const ok = try runner.waitUntilNotVisible(device, wanted, try optionalParamU64(params, "timeoutMs", 5000), live_trace, .{});
        try writeResultRaw(writer, id, if (ok) "true" else "false");
        return;
    }
    if (std.mem.eql(u8, method, "assert.visible")) {
        const wanted = try parseParamSelector(allocator, params);
        defer wanted.deinit(allocator);
        if (!try runner.waitUntilVisible(device, wanted, try optionalParamU64(params, "timeoutMs", 5000), live_trace, .{})) return error.AssertionFailed;
        try writeResultRaw(writer, id, "true");
        return;
    }
    if (std.mem.eql(u8, method, "assert.notVisible")) {
        const wanted = try parseParamSelector(allocator, params);
        defer wanted.deinit(allocator);
        if (!try runner.waitUntilNotVisible(device, wanted, try optionalParamU64(params, "timeoutMs", 5000), live_trace, .{})) return error.AssertionFailed;
        try writeResultRaw(writer, id, "true");
        return;
    }
    if (std.mem.eql(u8, method, "trace.events")) {
        const after_seq = try optionalParamU64(params, "afterSeq", 0);
        const limit = @min(try optionalParamU64(params, "limit", 100), 1000);
        try writeTraceEventsResult(allocator, writer, id, live_trace, after_seq, limit);
        return;
    }
    if (std.mem.eql(u8, method, "trace.export")) {
        const tw = live_trace orelse {
            try writeResultRaw(writer, id, "{\"traceDir\":null,\"message\":\"start zmr serve with --trace-dir to enable live RPC trace export\"}");
            return;
        };
        const out_path = try requiredParamString(params, "out");
        const redact = try optionalParamBool(params, "redact", false);
        const omit_screenshots = try optionalParamBool(params, "omitScreenshots", false);
        const effective_redact = redact or omit_screenshots;
        try tw.recordEvent("trace.export", "{\"status\":\"started\"}");
        try tw.flushManifest();
        try bundle.exportTraceBundleWithOptions(allocator, tw.root_dir, out_path, .{
            .redact = effective_redact,
            .omit_screenshots = omit_screenshots,
        });
        try writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
        try writeId(writer, id);
        try writer.writeAll(",\"result\":{\"traceDir\":");
        try trace.writeJsonString(writer, tw.root_dir);
        try writer.writeAll(",\"out\":");
        try trace.writeJsonString(writer, out_path);
        try writer.writeAll(",\"redacted\":");
        try writer.writeAll(if (effective_redact) "true" else "false");
        try writer.writeAll(",\"omitScreenshots\":");
        try writer.writeAll(if (omit_screenshots) "true" else "false");
        try writer.writeAll("}}\n");
        return;
    }

    try writeError(writer, id, -32601, "method not found");
}

fn parseParamSelector(allocator: std.mem.Allocator, params: ?std.json.Value) !selector.Selector {
    const selector_value = paramField(params, "selector") orelse return error.MissingSelector;
    return try selector.parseFromJson(allocator, selector_value);
}

fn parseParamSelectors(allocator: std.mem.Allocator, params: ?std.json.Value) ![]selector.Selector {
    const selectors_value = paramField(params, "selectors") orelse return error.MissingSelectors;
    if (selectors_value != .array) return error.SelectorsMustBeArray;
    var selectors = std.ArrayList(selector.Selector).empty;
    errdefer {
        for (selectors.items) |wanted| wanted.deinit(allocator);
        selectors.deinit(allocator);
    }
    for (selectors_value.array.items) |selector_value| {
        try selectors.append(allocator, try selector.parseFromJson(allocator, selector_value));
    }
    if (selectors.items.len == 0) return error.SelectorsMustNotBeEmpty;
    return try selectors.toOwnedSlice(allocator);
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

fn requiredParamI32(params: ?std.json.Value, key: []const u8) !i32 {
    const value = paramField(params, key) orelse return error.MissingParam;
    return switch (value) {
        .integer => |actual| @as(i32, @intCast(actual)),
        else => error.ParamMustBeInteger,
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

fn optionalParamDirection(params: ?std.json.Value, key: []const u8, default_value: scenario.ScrollDirection) !scenario.ScrollDirection {
    const value = paramField(params, key) orelse return default_value;
    if (value != .string) return error.ParamMustBeString;
    if (std.mem.eql(u8, value.string, "down")) return .down;
    if (std.mem.eql(u8, value.string, "up")) return .up;
    return error.UnknownScrollDirection;
}

fn writeTraceEventsResult(
    allocator: std.mem.Allocator,
    writer: anytype,
    id: ?std.json.Value,
    live_trace: ?*trace.TraceWriter,
    after_seq: u64,
    limit: u64,
) !void {
    const tw = live_trace orelse {
        try writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
        try writeId(writer, id);
        try writer.print(",\"result\":{{\"traceDir\":null,\"afterSeq\":{d},\"nextSeq\":{d},\"latestSeq\":0,\"events\":[]}}}}\n", .{ after_seq, after_seq });
        return;
    };

    const events_path = try std.fs.path.join(allocator, &.{ tw.root_dir, "events.jsonl" });
    defer allocator.free(events_path);
    const content = std.fs.cwd().readFileAlloc(allocator, events_path, 64 * 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => try allocator.dupe(u8, ""),
        else => return err,
    };
    defer allocator.free(content);

    try writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
    try writeId(writer, id);
    try writer.writeAll(",\"result\":{\"traceDir\":");
    try trace.writeJsonString(writer, tw.root_dir);
    try writer.print(",\"afterSeq\":{d},\"nextSeq\":", .{after_seq});

    var events_json = std.ArrayList(u8).empty;
    defer events_json.deinit(allocator);
    var events_writer = events_json.writer(allocator);
    var next_seq = after_seq;
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
        if (emitted > 0) try events_writer.writeAll(",");
        try events_writer.writeAll(line);
        next_seq = seq;
        emitted += 1;
    }

    try writer.print("{d},\"latestSeq\":{d},\"events\":[", .{ next_seq, tw.event_count });
    try writer.writeAll(events_json.items);
    try writer.writeAll("]}}\n");
}

fn recordRpcEvent(tw: *trace.TraceWriter, kind: []const u8, method: []const u8, id: ?std.json.Value) !void {
    var payload = std.ArrayList(u8).empty;
    defer payload.deinit(tw.allocator);
    const writer = payload.writer(tw.allocator);
    try writer.writeAll("{\"method\":");
    try trace.writeJsonString(writer, method);
    try writer.writeAll(",\"id\":");
    try writeId(writer, id);
    try writer.writeAll("}");
    try tw.recordEvent(kind, payload.items);
}

fn recordRpcErrorEvent(tw: *trace.TraceWriter, method: []const u8, id: ?std.json.Value, err: anyerror) !void {
    var payload = std.ArrayList(u8).empty;
    defer payload.deinit(tw.allocator);
    const writer = payload.writer(tw.allocator);
    try writer.writeAll("{\"method\":");
    try trace.writeJsonString(writer, method);
    try writer.writeAll(",\"id\":");
    try writeId(writer, id);
    try writer.writeAll(",\"error\":");
    try trace.writeJsonString(writer, @errorName(err));
    try writer.writeAll("}");
    try tw.recordEvent("rpc.error", payload.items);
}

fn recordRpcSimplePayload(tw: *trace.TraceWriter, kind: []const u8, key: []const u8, value: []const u8) !void {
    var payload = std.ArrayList(u8).empty;
    defer payload.deinit(tw.allocator);
    const writer = payload.writer(tw.allocator);
    try writer.writeAll("{");
    try trace.writeJsonString(writer, key);
    try writer.writeAll(":");
    try trace.writeJsonString(writer, value);
    try writer.writeAll("}");
    try tw.recordEvent(kind, payload.items);
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

fn writeErrorWithPublicCode(
    writer: anytype,
    id: ?std.json.Value,
    code: i32,
    message: []const u8,
    public_code: ?[]const u8,
) !void {
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

test "json rpc dispatches core action wait assertion and trace methods" {
    const fake_device = @import("fake_device.zig");
    const types = @import("types.zig");
    const allocator = std.testing.allocator;

    var snapshots = std.ArrayList(types.ObservationSnapshot).empty;
    defer {
        for (snapshots.items) |snap| snap.deinit(allocator);
        snapshots.deinit(allocator);
    }
    try appendRpcSnapshot(allocator, &snapshots, "rpc-observe", "Observed");
    try appendRpcSnapshot(allocator, &snapshots, "rpc-tap", "Tap");
    try appendRpcSnapshot(allocator, &snapshots, "rpc-type", "Field");
    try appendRpcSnapshot(allocator, &snapshots, "rpc-erase", "Field");
    try appendRpcSnapshot(allocator, &snapshots, "rpc-scroll", "Scroll");
    try appendRpcSnapshot(allocator, &snapshots, "rpc-visible", "Visible");
    try appendRpcSnapshot(allocator, &snapshots, "rpc-any", "Any");
    try appendRpcSnapshot(allocator, &snapshots, "rpc-gone", "Other");
    try appendRpcSnapshot(allocator, &snapshots, "rpc-assert-visible", "Assert");
    try appendRpcSnapshot(allocator, &snapshots, "rpc-assert-not-visible", "Other");

    var fake = fake_device.FakeDevice.init(allocator, snapshots.items);
    defer fake.deinit();

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    const writer = out.writer(allocator);

    try dispatchLine(allocator, &fake, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"runner.capabilities\",\"params\":{}}", writer);
    try dispatchLine(allocator, &fake, "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"device.list\",\"params\":{}}", writer);
    try dispatchLine(allocator, &fake, "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"session.create\",\"params\":{}}", writer);
    try dispatchLine(allocator, &fake, "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"session.close\",\"params\":{}}", writer);
    try dispatchLine(allocator, &fake, "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"app.install\",\"params\":{\"path\":\"/tmp/app.apk\"}}", writer);
    try dispatchLine(allocator, &fake, "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"app.launch\",\"params\":{}}", writer);
    try dispatchLine(allocator, &fake, "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"app.openLink\",\"params\":{\"url\":\"exampleapp://probe\"}}", writer);
    try dispatchLine(allocator, &fake, "{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"app.clearState\",\"params\":{}}", writer);
    try dispatchLine(allocator, &fake, "{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"app.stop\",\"params\":{}}", writer);
    try dispatchLine(allocator, &fake, "{\"jsonrpc\":\"2.0\",\"id\":10,\"method\":\"observe.snapshot\",\"params\":{}}", writer);
    try dispatchLine(allocator, &fake, "{\"jsonrpc\":\"2.0\",\"id\":11,\"method\":\"ui.tap\",\"params\":{\"selector\":{\"text\":\"Tap\"}}}", writer);
    try dispatchLine(allocator, &fake, "{\"jsonrpc\":\"2.0\",\"id\":12,\"method\":\"ui.type\",\"params\":{\"selector\":{\"text\":\"Field\"},\"text\":\"typed\"}}", writer);
    try dispatchLine(allocator, &fake, "{\"jsonrpc\":\"2.0\",\"id\":13,\"method\":\"ui.eraseText\",\"params\":{\"selector\":{\"text\":\"Field\"},\"maxChars\":9}}", writer);
    try dispatchLine(allocator, &fake, "{\"jsonrpc\":\"2.0\",\"id\":14,\"method\":\"ui.hideKeyboard\",\"params\":{}}", writer);
    try dispatchLine(allocator, &fake, "{\"jsonrpc\":\"2.0\",\"id\":15,\"method\":\"ui.swipe\",\"params\":{\"x1\":1,\"y1\":2,\"x2\":3,\"y2\":4,\"durationMs\":5}}", writer);
    try dispatchLine(allocator, &fake, "{\"jsonrpc\":\"2.0\",\"id\":16,\"method\":\"ui.pressBack\",\"params\":{}}", writer);
    try dispatchLine(allocator, &fake, "{\"jsonrpc\":\"2.0\",\"id\":17,\"method\":\"ui.scrollUntilVisible\",\"params\":{\"selector\":{\"text\":\"Scroll\"},\"direction\":\"down\",\"timeoutMs\":10}}", writer);
    try dispatchLine(allocator, &fake, "{\"jsonrpc\":\"2.0\",\"id\":18,\"method\":\"wait.until\",\"params\":{\"visible\":{\"text\":\"Visible\"},\"timeoutMs\":10}}", writer);
    try dispatchLine(allocator, &fake, "{\"jsonrpc\":\"2.0\",\"id\":19,\"method\":\"wait.any\",\"params\":{\"selectors\":[{\"text\":\"Missing\"},{\"text\":\"Any\"}],\"timeoutMs\":10}}", writer);
    try dispatchLine(allocator, &fake, "{\"jsonrpc\":\"2.0\",\"id\":20,\"method\":\"wait.gone\",\"params\":{\"selector\":{\"text\":\"Gone\"},\"timeoutMs\":10}}", writer);
    try dispatchLine(allocator, &fake, "{\"jsonrpc\":\"2.0\",\"id\":21,\"method\":\"assert.visible\",\"params\":{\"selector\":{\"text\":\"Assert\"},\"timeoutMs\":10}}", writer);
    try dispatchLine(allocator, &fake, "{\"jsonrpc\":\"2.0\",\"id\":22,\"method\":\"assert.notVisible\",\"params\":{\"selector\":{\"text\":\"Gone\"},\"timeoutMs\":10}}", writer);
    try dispatchLine(allocator, &fake, "{\"jsonrpc\":\"2.0\",\"id\":23,\"method\":\"trace.export\",\"params\":{}}", writer);

    try std.testing.expectEqualStrings("/tmp/app.apk", fake.installed_path.?);
    try std.testing.expect(fake.launched);
    try std.testing.expect(fake.stopped);
    try std.testing.expect(fake.cleared);
    try std.testing.expectEqualStrings("exampleapp://probe", fake.opened_link.?);
    try std.testing.expectEqual(@as(usize, 3), fake.taps);
    try std.testing.expectEqual(@as(usize, 1), fake.typed_text.items.len);
    try std.testing.expectEqualStrings("typed", fake.typed_text.items[0]);
    try std.testing.expectEqual(@as(usize, 1), fake.erases);
    try std.testing.expectEqual(@as(u32, 9), fake.last_erase_chars);
    try std.testing.expectEqual(@as(usize, 1), fake.hides_keyboard);
    try std.testing.expectEqual(@as(usize, 1), fake.presses_back);
    try std.testing.expectEqual(@as(usize, 1), fake.swipes);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"methods\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"version\":\"0.1.0-dev.1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"protocolVersion\":\"2026-04-28\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"protocol\":{\"version\":\"2026-04-28\",\"minimumCompatibleVersion\":\"2026-04-28\",\"stability\":\"dev-preview\",\"breakingChangePolicy\":\"version-and-changelog\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"platforms\":[\"android\",\"ios\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"platformSupport\":{\"android\":{\"status\":\"supported\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"ios\":{\"status\":\"supported\",\"deviceTypes\":[\"simulator\"],\"automation\":[\"simctl\",\"xctest-shim\"],\"physicalDevices\":false}") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"iosPreview\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"serial\":\"fake-device-1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"sessionId\":\"default\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"text\":\"Observed\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"matchedIndex\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"traceDir\":null") != null);
}

test "json rpc writes parse request method and execution errors" {
    const fake_device = @import("fake_device.zig");
    const types = @import("types.zig");
    const allocator = std.testing.allocator;
    const snapshots = try allocator.alloc(types.ObservationSnapshot, 0);
    defer allocator.free(snapshots);

    var fake = fake_device.FakeDevice.init(allocator, snapshots);
    defer fake.deinit();

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    const writer = out.writer(allocator);

    try dispatchLine(allocator, &fake, "{bad json", writer);
    try dispatchLine(allocator, &fake, "[]", writer);
    try dispatchLine(allocator, &fake, "{\"jsonrpc\":\"2.0\",\"id\":\"abc\",\"params\":{}}", writer);
    try dispatchLine(allocator, &fake, "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":3,\"params\":{}}", writer);
    try dispatchLine(allocator, &fake, "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"missing.method\",\"params\":{}}", writer);
    try dispatchLine(allocator, &fake, "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"ui.swipe\",\"params\":{\"x1\":1}}", writer);

    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"code\":-32700") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"code\":-32600") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"id\":\"abc\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"code\":-32601") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"publicCode\":\"cli.missing_param\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "MissingParam") != null);
}

test "json rpc live trace records session events and exports a bundle" {
    const fake_device = @import("fake_device.zig");
    const types = @import("types.zig");
    const allocator = std.testing.allocator;
    const trace_dir = "zig-cache-test-rpc-live-trace";
    const out_path = trace_dir ++ ".zmrtrace";
    std.fs.cwd().deleteTree(trace_dir) catch {};
    defer std.fs.cwd().deleteTree(trace_dir) catch {};
    defer std.fs.cwd().deleteFile(out_path) catch {};

    var snapshots = std.ArrayList(types.ObservationSnapshot).empty;
    defer {
        for (snapshots.items) |snap| snap.deinit(allocator);
        snapshots.deinit(allocator);
    }
    try appendRpcSnapshot(allocator, &snapshots, "rpc-live-observe", "Live Trace");

    var fake = fake_device.FakeDevice.init(allocator, snapshots.items);
    defer fake.deinit();

    var live_trace = try trace.TraceWriter.init(allocator, trace_dir);
    defer live_trace.deinit();
    try live_trace.startManifest("json-rpc session", "com.example.mobiletest");

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    const writer = out.writer(allocator);

    try dispatchLineWithTrace(allocator, &fake, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"session.create\",\"params\":{}}", writer, &live_trace);
    try dispatchLineWithTrace(allocator, &fake, "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"app.openLink\",\"params\":{\"url\":\"exampleapp://live\"}}", writer, &live_trace);
    try dispatchLineWithTrace(allocator, &fake, "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"observe.snapshot\",\"params\":{}}", writer, &live_trace);
    try dispatchLineWithTrace(allocator, &fake, "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"trace.export\",\"params\":{\"out\":\"zig-cache-test-rpc-live-trace.zmrtrace\",\"redact\":true,\"omitScreenshots\":true}}", writer, &live_trace);

    const events_path = try std.fs.path.join(allocator, &.{ trace_dir, "events.jsonl" });
    defer allocator.free(events_path);
    const events = try std.fs.cwd().readFileAlloc(allocator, events_path, 1024 * 1024);
    defer allocator.free(events);

    try std.testing.expect(std.mem.indexOf(u8, events, "\"kind\":\"rpc.request\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"method\":\"app.openLink\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"kind\":\"observe.snapshot\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"kind\":\"trace.export\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"out\":\"zig-cache-test-rpc-live-trace.zmrtrace\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"omitScreenshots\":true") != null);
    try std.fs.cwd().access(out_path, .{});
}

test "json rpc trace events returns live events after a cursor" {
    const fake_device = @import("fake_device.zig");
    const types = @import("types.zig");
    const allocator = std.testing.allocator;
    const trace_dir = "zig-cache-test-rpc-event-stream";
    std.fs.cwd().deleteTree(trace_dir) catch {};
    defer std.fs.cwd().deleteTree(trace_dir) catch {};

    var snapshots = std.ArrayList(types.ObservationSnapshot).empty;
    defer {
        for (snapshots.items) |snap| snap.deinit(allocator);
        snapshots.deinit(allocator);
    }
    try appendRpcSnapshot(allocator, &snapshots, "rpc-stream-observe", "Stream Trace");

    var fake = fake_device.FakeDevice.init(allocator, snapshots.items);
    defer fake.deinit();

    var live_trace = try trace.TraceWriter.init(allocator, trace_dir);
    defer live_trace.deinit();
    try live_trace.startManifest("json-rpc event stream", "com.example.mobiletest");

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    const writer = out.writer(allocator);

    try dispatchLineWithTrace(allocator, &fake, "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"session.create\",\"params\":{}}", writer, &live_trace);
    try dispatchLineWithTrace(allocator, &fake, "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"observe.snapshot\",\"params\":{}}", writer, &live_trace);
    try dispatchLineWithTrace(allocator, &fake, "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"trace.events\",\"params\":{\"afterSeq\":2,\"limit\":10}}", writer, &live_trace);

    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"traceDir\":\"zig-cache-test-rpc-event-stream\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"afterSeq\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"nextSeq\":6") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"latestSeq\":6") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"kind\":\"observe.snapshot\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "\"method\":\"trace.events\"") != null);
}

test "json rpc protocol fixtures match exact core session responses" {
    const fake_device = @import("fake_device.zig");
    const types = @import("types.zig");
    const allocator = std.testing.allocator;

    const snapshots = try allocator.alloc(types.ObservationSnapshot, 0);
    defer allocator.free(snapshots);
    var fake = fake_device.FakeDevice.init(allocator, snapshots);
    defer fake.deinit();

    const requests = try std.fs.cwd().readFileAlloc(allocator, "docs/protocol-fixtures/core-session.requests.jsonl", 64 * 1024);
    defer allocator.free(requests);
    const expected = try std.fs.cwd().readFileAlloc(allocator, "docs/protocol-fixtures/core-session.responses.jsonl", 64 * 1024);
    defer allocator.free(expected);

    var out = std.ArrayList(u8).empty;
    defer out.deinit(allocator);
    const writer = out.writer(allocator);

    var lines = std.mem.splitScalar(u8, requests, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r\n");
        if (line.len == 0) continue;
        try dispatchLine(allocator, &fake, line, writer);
    }

    try std.testing.expectEqualStrings(expected, out.items);
}

fn appendRpcSnapshot(
    allocator: std.mem.Allocator,
    snapshots: *std.ArrayList(@import("types.zig").ObservationSnapshot),
    id: []const u8,
    text: []const u8,
) !void {
    const types = @import("types.zig");
    const nodes = try allocator.alloc(types.UiNode, 1);
    nodes[0] = .{
        .stable_id = try std.fmt.allocPrint(allocator, "node-{s}", .{id}),
        .class_name = try allocator.dupe(u8, "android.widget.TextView"),
        .text = try allocator.dupe(u8, text),
        .bounds = .{ .x = 10, .y = 20, .width = 100, .height = 40 },
    };
    try snapshots.append(allocator, .{
        .id = try allocator.dupe(u8, id),
        .timestamp_ms = @as(i64, @intCast(snapshots.items.len + 1)),
        .viewport = .{ .width = 1080, .height = 2400 },
        .nodes = nodes,
    });
}
