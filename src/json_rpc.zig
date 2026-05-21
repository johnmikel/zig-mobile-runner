const std = @import("std");
const errors = @import("errors.zig");
const methods = @import("json_rpc_methods.zig");
const protocol = @import("json_rpc_protocol.zig");
const trace = @import("trace.zig");

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
            try protocol.writeError(stdout, null, -32700, @errorName(err));
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

pub fn dispatchLine(allocator: std.mem.Allocator, device: anytype, line: []const u8, writer: anytype) !void {
    try dispatchLineWithTrace(allocator, device, line, writer, null);
}

pub fn dispatchLineWithTrace(
    allocator: std.mem.Allocator,
    device: anytype,
    line: []const u8,
    writer: anytype,
    live_trace: ?*trace.TraceWriter,
) !void {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, line, .{}) catch |err| {
        try protocol.writeError(writer, null, -32700, @errorName(err));
        return;
    };
    defer parsed.deinit();

    if (parsed.value != .object) {
        try protocol.writeError(writer, null, -32600, "request must be an object");
        return;
    }
    const object = parsed.value.object;
    const id = object.get("id");
    const method_value = object.get("method") orelse {
        try protocol.writeError(writer, id, -32600, "missing method");
        return;
    };
    if (method_value != .string) {
        try protocol.writeError(writer, id, -32600, "method must be a string");
        return;
    }
    const params = object.get("params");

    if (live_trace) |tw| try recordRpcEvent(tw, "rpc.request", method_value.string, id);
    methods.dispatchMethod(allocator, device, method_value.string, params, id, writer, live_trace) catch |err| {
        if (live_trace) |tw| try recordRpcErrorEvent(tw, method_value.string, id, err);
        const classified = errors.classify(err);
        try protocol.writeErrorWithPublicCode(writer, id, -32000, @errorName(err), classified.code);
        return;
    };
    if (live_trace) |tw| try recordRpcEvent(tw, "rpc.response", method_value.string, id);
}

fn recordRpcEvent(tw: *trace.TraceWriter, kind: []const u8, method: []const u8, id: ?std.json.Value) !void {
    var payload = std.ArrayList(u8).empty;
    defer payload.deinit(tw.allocator);
    const writer = payload.writer(tw.allocator);
    try writer.writeAll("{\"method\":");
    try trace.writeJsonString(writer, method);
    try writer.writeAll(",\"id\":");
    try protocol.writeId(writer, id);
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
    try protocol.writeId(writer, id);
    try writer.writeAll(",\"error\":");
    try trace.writeJsonString(writer, @errorName(err));
    try writer.writeAll("}");
    try tw.recordEvent("rpc.error", payload.items);
}
