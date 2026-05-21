const std = @import("std");
const protocol = @import("json_rpc_protocol.zig");
const semantic = @import("semantic.zig");
const trace = @import("trace.zig");
const types = @import("types.zig");

pub const Format = enum { raw, semantic };

pub fn writeResult(writer: anytype, id: ?std.json.Value, snap: types.ObservationSnapshot, format: Format) !void {
    try writer.writeAll("{\"jsonrpc\":\"2.0\",\"id\":");
    try protocol.writeId(writer, id);
    try writer.writeAll(",\"result\":");
    switch (format) {
        .raw => try trace.writeSnapshotJson(writer, snap),
        .semantic => try semantic.writeSemanticSnapshotJson(writer, snap),
    }
    try writer.writeAll("}\n");
}

pub fn recordArtifact(tw: *trace.TraceWriter, kind: []const u8, snap: types.ObservationSnapshot) !void {
    const path = try tw.writeSnapshot(snap);
    defer tw.allocator.free(path);
    var payload = std.ArrayList(u8).empty;
    defer payload.deinit(tw.allocator);
    try payload.writer(tw.allocator).writeAll("{\"path\":");
    try trace.writeJsonString(payload.writer(tw.allocator), path);
    try payload.writer(tw.allocator).writeAll(",\"snapshotId\":");
    try trace.writeJsonString(payload.writer(tw.allocator), snap.id);
    try payload.writer(tw.allocator).writeAll("}");
    try tw.recordEvent(kind, payload.items);
}
