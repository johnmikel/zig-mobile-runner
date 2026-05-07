const std = @import("std");
const types = @import("types.zig");
const selector = @import("selector.zig");
const version = @import("version.zig");

pub const CaptureOptions = struct {
    capture_screenshots: bool = true,
    capture_hierarchy: bool = true,
    capture_logs: bool = true,
    capture_screen_recording: bool = false,
    redaction: RedactionRules = .{},
};

pub const RedactionRules = struct {
    denylist_text: []const []const u8 = &.{},
    allowlist_text: []const []const u8 = &.{},
    denylist_resource_ids: []const []const u8 = &.{},
    allowlist_resource_ids: []const []const u8 = &.{},
};

pub const TraceWriter = struct {
    allocator: std.mem.Allocator,
    root_dir: []const u8,
    event_count: usize = 0,
    snapshot_count: usize = 0,
    manifest: ?Manifest = null,
    capture: CaptureOptions = .{},

    pub fn init(allocator: std.mem.Allocator, root_dir: []const u8) !TraceWriter {
        return try initWithOptions(allocator, root_dir, .{});
    }

    pub fn initWithOptions(allocator: std.mem.Allocator, root_dir: []const u8, capture: CaptureOptions) !TraceWriter {
        try std.fs.cwd().makePath(root_dir);
        try resetTraceDirectory(allocator, root_dir);
        const artifacts_path = try std.fs.path.join(allocator, &.{ root_dir, "artifacts" });
        defer allocator.free(artifacts_path);
        try std.fs.cwd().makePath(artifacts_path);
        return .{
            .allocator = allocator,
            .root_dir = try allocator.dupe(u8, root_dir),
            .capture = capture,
        };
    }

    pub fn deinit(self: *TraceWriter) void {
        if (self.manifest) |*manifest| manifest.deinit(self.allocator);
        self.allocator.free(self.root_dir);
    }

    pub fn startManifest(self: *TraceWriter, scenario_name: []const u8, app_id: ?[]const u8) !void {
        if (self.manifest) |*existing| existing.deinit(self.allocator);
        self.manifest = .{
            .scenario_name = try self.allocator.dupe(u8, scenario_name),
            .app_id = try dupeOptional(self.allocator, app_id),
            .status = try self.allocator.dupe(u8, "running"),
            .started_at_ms = std.time.milliTimestamp(),
        };
        try self.writeManifest();
    }

    pub const FinishManifestOptions = struct {
        status: []const u8,
        failed_step_index: ?usize = null,
        error_name: ?[]const u8 = null,
        report_path: ?[]const u8 = null,
    };

    pub fn finishManifest(self: *TraceWriter, options: FinishManifestOptions) !void {
        if (self.manifest == null) return;
        var manifest = &self.manifest.?;
        self.allocator.free(manifest.status);
        manifest.status = try self.allocator.dupe(u8, options.status);
        manifest.ended_at_ms = std.time.milliTimestamp();
        manifest.failed_step_index = options.failed_step_index;
        if (manifest.error_name) |value| self.allocator.free(value);
        manifest.error_name = try dupeOptional(self.allocator, options.error_name);
        if (options.report_path) |value| {
            if (manifest.report_path) |old| self.allocator.free(old);
            manifest.report_path = try self.allocator.dupe(u8, value);
        }
        try self.writeManifest();
    }

    pub fn attachReport(self: *TraceWriter, report_path: []const u8) !void {
        if (self.manifest == null) return;
        var manifest = &self.manifest.?;
        if (manifest.report_path) |old| self.allocator.free(old);
        manifest.report_path = try self.allocator.dupe(u8, report_path);
        try self.writeManifest();
    }

    pub fn nextSnapshotId(self: *TraceWriter) ![]const u8 {
        self.snapshot_count += 1;
        return try std.fmt.allocPrint(self.allocator, "snapshot-{d}", .{self.snapshot_count});
    }

    pub fn artifactPath(self: *TraceWriter, name: []const u8) ![]const u8 {
        return try std.fs.path.join(self.allocator, &.{ self.root_dir, "artifacts", name });
    }

    pub fn writeArtifact(self: *TraceWriter, name: []const u8, bytes: []const u8) ![]const u8 {
        const path = try self.artifactPath(name);
        errdefer self.allocator.free(path);
        var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
        defer file.close();
        try file.writeAll(bytes);
        return path;
    }

    pub fn recordEvent(self: *TraceWriter, kind: []const u8, payload: []const u8) !void {
        self.event_count += 1;
        const path = try std.fs.path.join(self.allocator, &.{ self.root_dir, "events.jsonl" });
        defer self.allocator.free(path);
        var file = try std.fs.cwd().createFile(path, .{ .truncate = false });
        defer file.close();
        try file.seekFromEnd(0);
        var write_buffer: [4096]u8 = undefined;
        var file_writer = file.writerStreaming(&write_buffer);
        const writer = &file_writer.interface;
        try writer.print(
            "{{\"seq\":{d},\"timestampMs\":{d},\"kind\":\"{s}\",\"payload\":",
            .{ self.event_count, std.time.milliTimestamp(), kind },
        );
        try writeRedactedJsonPayload(self.allocator, writer, payload, self.capture.redaction);
        try writer.writeAll("}\n");
        try writer.flush();
        try self.writeManifest();
    }

    pub fn writeSnapshot(self: *TraceWriter, snapshot: types.ObservationSnapshot) ![]const u8 {
        const file_name = try std.fmt.allocPrint(self.allocator, "{s}.json", .{snapshot.id});
        defer self.allocator.free(file_name);
        const path = try self.artifactPath(file_name);
        errdefer self.allocator.free(path);
        var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
        defer file.close();
        var write_buffer: [8192]u8 = undefined;
        var file_writer = file.writer(&write_buffer);
        try writeSnapshotJsonRedacted(&file_writer.interface, snapshot, self.capture.redaction);
        try file_writer.interface.flush();
        return path;
    }

    pub fn flushManifest(self: *TraceWriter) !void {
        try self.writeManifest();
    }

    fn writeManifest(self: *TraceWriter) !void {
        if (self.manifest == null) return;
        const manifest = self.manifest.?;
        const path = try std.fs.path.join(self.allocator, &.{ self.root_dir, "trace.json" });
        defer self.allocator.free(path);
        var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
        defer file.close();
        var write_buffer: [4096]u8 = undefined;
        var file_writer = file.writer(&write_buffer);
        const writer = &file_writer.interface;

        try writer.writeAll("{");
        try writer.writeAll("\"schemaVersion\":1");
        try writer.writeAll(",\"runnerVersion\":");
        try writeJsonString(writer, version.runner_version);
        try writer.writeAll(",\"protocolVersion\":");
        try writeJsonString(writer, version.protocol_version);
        try writer.writeAll(",\"scenarioName\":");
        try writeJsonString(writer, manifest.scenario_name);
        try writer.writeAll(",\"appId\":");
        if (manifest.app_id) |app_id| {
            try writeJsonString(writer, app_id);
        } else {
            try writer.writeAll("null");
        }
        try writer.writeAll(",\"status\":");
        try writeJsonString(writer, manifest.status);
        try writer.print(",\"startedAtMs\":{d}", .{manifest.started_at_ms});
        try writer.writeAll(",\"endedAtMs\":");
        if (manifest.ended_at_ms) |value| {
            try writer.print("{d}", .{value});
        } else {
            try writer.writeAll("null");
        }
        try writer.writeAll(",\"durationMs\":");
        if (manifest.ended_at_ms) |ended| {
            try writer.print("{d}", .{ended - manifest.started_at_ms});
        } else {
            try writer.writeAll("null");
        }
        try writer.writeAll(",\"failedStepIndex\":");
        if (manifest.failed_step_index) |value| {
            try writer.print("{d}", .{value});
        } else {
            try writer.writeAll("null");
        }
        try writer.writeAll(",\"error\":");
        if (manifest.error_name) |value| {
            try writeJsonString(writer, value);
        } else {
            try writer.writeAll("null");
        }
        try writer.writeAll(",\"eventsPath\":\"events.jsonl\"");
        try writer.writeAll(",\"artifactsDir\":\"artifacts\"");
        try writer.print(",\"eventCount\":{d}", .{self.event_count});
        try writer.print(",\"snapshotCount\":{d}", .{self.snapshot_count});
        try writer.writeAll(",\"reportPath\":");
        if (manifest.report_path) |value| {
            try writeJsonString(writer, value);
        } else {
            try writer.writeAll("null");
        }
        try writer.writeAll("}\n");
        try writer.flush();
    }
};

fn resetTraceDirectory(allocator: std.mem.Allocator, root_dir: []const u8) !void {
    const stale_files = [_][]const u8{ "events.jsonl", "trace.json", "report.html" };
    for (stale_files) |name| {
        const path = try std.fs.path.join(allocator, &.{ root_dir, name });
        defer allocator.free(path);
        std.fs.cwd().deleteFile(path) catch |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        };
    }

    const artifacts_path = try std.fs.path.join(allocator, &.{ root_dir, "artifacts" });
    defer allocator.free(artifacts_path);
    var artifacts_exists = true;
    std.fs.cwd().access(artifacts_path, .{}) catch |err| switch (err) {
        error.FileNotFound => artifacts_exists = false,
        else => return err,
    };
    if (artifacts_exists) try std.fs.cwd().deleteTree(artifacts_path);
}

const Manifest = struct {
    scenario_name: []const u8,
    app_id: ?[]const u8 = null,
    status: []const u8,
    started_at_ms: i64,
    ended_at_ms: ?i64 = null,
    failed_step_index: ?usize = null,
    error_name: ?[]const u8 = null,
    report_path: ?[]const u8 = null,

    fn deinit(self: *Manifest, allocator: std.mem.Allocator) void {
        allocator.free(self.scenario_name);
        if (self.app_id) |value| allocator.free(value);
        allocator.free(self.status);
        if (self.error_name) |value| allocator.free(value);
        if (self.report_path) |value| allocator.free(value);
    }
};

fn dupeOptional(allocator: std.mem.Allocator, value: ?[]const u8) !?[]const u8 {
    if (value) |actual| return try allocator.dupe(u8, actual);
    return null;
}

pub fn writeSnapshotJson(writer: anytype, snapshot: types.ObservationSnapshot) !void {
    try writer.writeAll("{");
    try jsonField(writer, "id", snapshot.id, true);
    try writer.print(",\"timestampMs\":{d}", .{snapshot.timestamp_ms});
    try writer.print(
        ",\"viewport\":{{\"width\":{d},\"height\":{d}}}",
        .{ snapshot.viewport.width, snapshot.viewport.height },
    );
    try writer.writeAll(",\"displayDensityDpi\":");
    if (snapshot.display_density_dpi) |density| {
        try writer.print("{d}", .{density});
    } else {
        try writer.writeAll("null");
    }
    try jsonNullableField(writer, "activePackage", snapshot.active_package);
    try jsonNullableField(writer, "activeActivity", snapshot.active_activity);
    try jsonNullableField(writer, "screenshotArtifact", snapshot.screenshot_artifact);
    try jsonNullableField(writer, "treeArtifact", snapshot.tree_artifact);
    try jsonNullableField(writer, "focusedNodeId", snapshot.focused_node_id);
    try jsonNullableField(writer, "logDelta", snapshot.log_delta);
    try writer.writeAll(",\"nodes\":[");
    for (snapshot.nodes, 0..) |node, index| {
        if (index > 0) try writer.writeAll(",");
        try writeNodeJson(writer, node);
    }
    try writer.writeAll("]}");
}

pub fn attachReportPath(allocator: std.mem.Allocator, root_dir: []const u8, report_path: []const u8) !void {
    const manifest_path = try std.fs.path.join(allocator, &.{ root_dir, "trace.json" });
    defer allocator.free(manifest_path);

    const content = std.fs.cwd().readFileAlloc(allocator, manifest_path, 1024 * 1024) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer allocator.free(content);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, content, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidTraceManifest;

    const arena_allocator = parsed.arena.allocator();
    const owned_report_path = try arena_allocator.dupe(u8, report_path);
    try parsed.value.object.put("reportPath", .{ .string = owned_report_path });

    var file = try std.fs.cwd().createFile(manifest_path, .{ .truncate = true });
    defer file.close();
    var write_buffer: [4096]u8 = undefined;
    var file_writer = file.writer(&write_buffer);
    try std.json.Stringify.value(parsed.value, .{}, &file_writer.interface);
    try file_writer.interface.writeByte('\n');
    try file_writer.interface.flush();
}

pub fn writeNodeJson(writer: anytype, node: types.UiNode) !void {
    try writer.writeAll("{");
    try jsonField(writer, "stableId", node.stable_id, true);
    try jsonField(writer, "className", node.class_name, false);
    try jsonNullableField(writer, "resourceId", node.resource_id);
    try jsonNullableField(writer, "text", node.text);
    try jsonNullableField(writer, "contentDesc", node.content_desc);
    try writer.print(
        ",\"bounds\":{{\"x\":{d},\"y\":{d},\"width\":{d},\"height\":{d}}}",
        .{ node.bounds.x, node.bounds.y, node.bounds.width, node.bounds.height },
    );
    try writer.print(
        ",\"enabled\":{},\"visible\":{},\"selected\":{}",
        .{ node.enabled, node.visible, node.selected },
    );
    try writer.writeAll("}");
}

fn writeSnapshotJsonRedacted(writer: anytype, snapshot: types.ObservationSnapshot, redaction: RedactionRules) !void {
    try writer.writeAll("{");
    try jsonField(writer, "id", snapshot.id, true);
    try writer.print(",\"timestampMs\":{d}", .{snapshot.timestamp_ms});
    try writer.print(
        ",\"viewport\":{{\"width\":{d},\"height\":{d}}}",
        .{ snapshot.viewport.width, snapshot.viewport.height },
    );
    try writer.writeAll(",\"displayDensityDpi\":");
    if (snapshot.display_density_dpi) |density| {
        try writer.print("{d}", .{density});
    } else {
        try writer.writeAll("null");
    }
    try jsonNullableField(writer, "activePackage", snapshot.active_package);
    try jsonNullableField(writer, "activeActivity", snapshot.active_activity);
    try jsonNullableField(writer, "screenshotArtifact", snapshot.screenshot_artifact);
    try jsonNullableField(writer, "treeArtifact", snapshot.tree_artifact);
    try jsonNullableField(writer, "focusedNodeId", snapshot.focused_node_id);
    try jsonNullableFieldRedacted(writer, "logDelta", snapshot.log_delta, redaction);
    try writer.writeAll(",\"nodes\":[");
    for (snapshot.nodes, 0..) |node, index| {
        if (index > 0) try writer.writeAll(",");
        try writeNodeJsonRedacted(writer, node, redaction);
    }
    try writer.writeAll("]}");
}

fn writeNodeJsonRedacted(writer: anytype, node: types.UiNode, redaction: RedactionRules) !void {
    try writer.writeAll("{");
    try jsonField(writer, "stableId", node.stable_id, true);
    try jsonField(writer, "className", node.class_name, false);
    const sensitive_node = if (node.resource_id) |id| isSensitiveResourceId(id, redaction) else false;
    try jsonNullableResourceIdRedacted(writer, "resourceId", node.resource_id, redaction);
    try jsonNullableFieldRedactedWithContext(writer, "text", node.text, sensitive_node, redaction);
    try jsonNullableFieldRedactedWithContext(writer, "contentDesc", node.content_desc, sensitive_node, redaction);
    try writer.print(
        ",\"bounds\":{{\"x\":{d},\"y\":{d},\"width\":{d},\"height\":{d}}}",
        .{ node.bounds.x, node.bounds.y, node.bounds.width, node.bounds.height },
    );
    try writer.print(
        ",\"enabled\":{},\"visible\":{},\"selected\":{}",
        .{ node.enabled, node.visible, node.selected },
    );
    try writer.writeAll("}");
}

pub fn writeSelectorJson(writer: anytype, wanted: selector.Selector) !void {
    try writer.writeAll("{");
    var first = true;
    if (wanted.id) |value| {
        try jsonField(writer, "id", value, first);
        first = false;
    }
    if (wanted.text) |value| {
        try jsonField(writer, "text", value, first);
        first = false;
    }
    if (wanted.text_contains) |value| {
        try jsonField(writer, "textContains", value, first);
        first = false;
    }
    if (wanted.content_desc) |value| {
        try jsonField(writer, "contentDesc", value, first);
        first = false;
    }
    if (wanted.content_desc_contains) |value| {
        try jsonField(writer, "contentDescContains", value, first);
        first = false;
    }
    if (wanted.class_name) |value| {
        try jsonField(writer, "className", value, first);
    }
    try writer.writeAll("}");
}

fn jsonField(writer: anytype, key: []const u8, value: []const u8, first: bool) !void {
    if (!first) try writer.writeAll(",");
    try writer.print("\"{s}\":", .{key});
    try writeJsonString(writer, value);
}

fn jsonNullableField(writer: anytype, key: []const u8, value: ?[]const u8) !void {
    try writer.print(",\"{s}\":", .{key});
    if (value) |actual| {
        try writeJsonString(writer, actual);
    } else {
        try writer.writeAll("null");
    }
}

fn jsonNullableFieldRedacted(writer: anytype, key: []const u8, value: ?[]const u8, redaction: RedactionRules) !void {
    try jsonNullableFieldRedactedWithContext(writer, key, value, false, redaction);
}

fn jsonNullableFieldRedactedWithContext(writer: anytype, key: []const u8, value: ?[]const u8, force_secret: bool, redaction: RedactionRules) !void {
    try writer.print(",\"{s}\":", .{key});
    if (value) |actual| {
        try writeRedactedJsonStringForKeyWithRules(writer, key, actual, force_secret, redaction);
    } else {
        try writer.writeAll("null");
    }
}

fn jsonNullableResourceIdRedacted(writer: anytype, key: []const u8, value: ?[]const u8, redaction: RedactionRules) !void {
    try writer.print(",\"{s}\":", .{key});
    if (value) |actual| {
        if (resourceIdDenied(actual, redaction) and !resourceIdAllowed(actual, redaction)) {
            try writeJsonString(writer, "[REDACTED:resourceId]");
        } else {
            try writeJsonString(writer, actual);
        }
    } else {
        try writer.writeAll("null");
    }
}

fn writeRedactedJsonPayload(allocator: std.mem.Allocator, writer: anytype, payload: []const u8, redaction: RedactionRules) !void {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, payload, .{}) catch {
        try writeRedactedJsonStringWithRules(writer, payload, redaction);
        return;
    };
    defer parsed.deinit();
    try writeJsonValueRedacted(writer, parsed.value, null, redaction);
}

fn writeJsonValueRedacted(writer: anytype, value: std.json.Value, key_context: ?[]const u8, redaction: RedactionRules) !void {
    switch (value) {
        .null => try writer.writeAll("null"),
        .bool => |actual| try writer.writeAll(if (actual) "true" else "false"),
        .integer => |actual| try writer.print("{d}", .{actual}),
        .float => |actual| try writer.print("{d}", .{actual}),
        .number_string => |actual| try writer.writeAll(actual),
        .string => |actual| {
            if (key_context) |key| {
                try writeRedactedJsonStringForKeyWithRules(writer, key, actual, false, redaction);
            } else {
                try writeRedactedJsonStringWithRules(writer, actual, redaction);
            }
        },
        .array => |array| {
            try writer.writeAll("[");
            for (array.items, 0..) |item, index| {
                if (index > 0) try writer.writeAll(",");
                try writeJsonValueRedacted(writer, item, key_context, redaction);
            }
            try writer.writeAll("]");
        },
        .object => |object| {
            try writer.writeAll("{");
            var first = true;
            var iterator = object.iterator();
            while (iterator.next()) |entry| {
                if (!first) try writer.writeAll(",");
                first = false;
                try writeJsonString(writer, entry.key_ptr.*);
                try writer.writeAll(":");
                try writeJsonValueRedacted(writer, entry.value_ptr.*, entry.key_ptr.*, redaction);
            }
            try writer.writeAll("}");
        },
    }
}

pub fn writeRedactedJsonString(writer: anytype, value: []const u8) !void {
    try writeRedactedJsonStringForKeyWithRules(writer, "", value, false, .{});
}

pub fn writeRedactedJsonStringForKey(writer: anytype, key: []const u8, value: []const u8, force_secret: bool) !void {
    try writeRedactedJsonStringForKeyWithRules(writer, key, value, force_secret, .{});
}

fn writeRedactedJsonStringWithRules(writer: anytype, value: []const u8, redaction: RedactionRules) !void {
    try writeRedactedJsonStringForKeyWithRules(writer, "", value, false, redaction);
}

fn writeRedactedJsonStringForKeyWithRules(writer: anytype, key: []const u8, value: []const u8, force_secret: bool, redaction: RedactionRules) !void {
    if (force_secret or isSensitiveLabel(key)) {
        try writeJsonString(writer, "[REDACTED:secret]");
    } else if (textDenied(value, redaction) and !textAllowed(value, redaction)) {
        try writeJsonString(writer, "[REDACTED:custom]");
    } else if (looksLikeToken(value)) {
        try writeJsonString(writer, "[REDACTED:token]");
    } else if (looksLikeEmail(value)) {
        try writeJsonString(writer, "[REDACTED:email]");
    } else {
        try writeJsonString(writer, value);
    }
}

pub fn writeJsonString(writer: anytype, value: []const u8) !void {
    try writer.writeAll("\"");
    for (value) |ch| {
        switch (ch) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            0...7, 11, 12, 14...31 => try writer.print("\\u{x:0>4}", .{ch}),
            else => try writer.writeAll(&.{ch}),
        }
    }
    try writer.writeAll("\"");
}

fn isSensitiveLabel(value: []const u8) bool {
    const needles = [_][]const u8{
        "password",
        "token",
        "secret",
        "authorization",
        "auth",
        "cookie",
        "apikey",
        "api_key",
        "bearer",
    };
    for (needles) |needle| {
        if (indexOfIgnoreCase(value, needle) != null) return true;
    }
    return false;
}

fn isSensitiveResourceId(value: []const u8, redaction: RedactionRules) bool {
    if (resourceIdAllowed(value, redaction)) return false;
    return isSensitiveLabel(value) or resourceIdDenied(value, redaction);
}

fn resourceIdDenied(value: []const u8, redaction: RedactionRules) bool {
    return matchesAnyIgnoreCase(value, redaction.denylist_resource_ids);
}

fn resourceIdAllowed(value: []const u8, redaction: RedactionRules) bool {
    return matchesAnyIgnoreCase(value, redaction.allowlist_resource_ids);
}

fn textDenied(value: []const u8, redaction: RedactionRules) bool {
    return matchesAnyIgnoreCase(value, redaction.denylist_text);
}

fn textAllowed(value: []const u8, redaction: RedactionRules) bool {
    return matchesAnyIgnoreCase(value, redaction.allowlist_text);
}

fn matchesAnyIgnoreCase(value: []const u8, needles: []const []const u8) bool {
    for (needles) |needle| {
        if (indexOfIgnoreCase(value, needle) != null) return true;
    }
    return false;
}

fn looksLikeEmail(value: []const u8) bool {
    if (value.len < 5 or value.len > 254) return false;
    if (std.mem.indexOfAny(u8, value, " \t\r\n<>") != null) return false;
    const at = std.mem.indexOfScalar(u8, value, '@') orelse return false;
    if (at == 0 or at + 3 >= value.len) return false;
    return std.mem.indexOfScalar(u8, value[at + 1 ..], '.') != null;
}

fn looksLikeToken(value: []const u8) bool {
    if (indexOfIgnoreCase(value, "bearer ") != null) return true;
    if (value.len < 40) return false;
    const first_dot = std.mem.indexOfScalar(u8, value, '.') orelse return false;
    const second_dot = std.mem.indexOfScalarPos(u8, value, first_dot + 1, '.') orelse return false;
    return second_dot + 1 < value.len;
}

fn indexOfIgnoreCase(haystack: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0 or needle.len > haystack.len) return null;
    var index: usize = 0;
    while (index + needle.len <= haystack.len) : (index += 1) {
        var matched = true;
        for (needle, 0..) |needle_ch, offset| {
            if (std.ascii.toLower(haystack[index + offset]) != std.ascii.toLower(needle_ch)) {
                matched = false;
                break;
            }
        }
        if (matched) return index;
    }
    return null;
}

test "snapshot json contains nodes" {
    const allocator = std.testing.allocator;
    var node = types.UiNode{
        .stable_id = try allocator.dupe(u8, "node-1"),
        .class_name = try allocator.dupe(u8, "android.widget.TextView"),
        .text = try allocator.dupe(u8, "Probe"),
    };
    defer node.deinit(allocator);
    const nodes = try allocator.alloc(types.UiNode, 1);
    defer allocator.free(nodes);
    nodes[0] = node;

    const snapshot = types.ObservationSnapshot{
        .id = try allocator.dupe(u8, "snapshot-1"),
        .timestamp_ms = 42,
        .nodes = nodes,
    };
    defer allocator.free(snapshot.id);

    var buffer = std.ArrayList(u8).empty;
    defer buffer.deinit(allocator);
    try writeSnapshotJson(buffer.writer(allocator), snapshot);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"nodes\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"displayDensityDpi\":null") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "Probe") != null);
}

test "trace writer appends events" {
    const allocator = std.testing.allocator;
    const dir = "zig-cache-test-trace-events";
    std.fs.cwd().deleteTree(dir) catch {};
    defer std.fs.cwd().deleteTree(dir) catch {};

    var writer = try TraceWriter.init(allocator, dir);
    defer writer.deinit();

    try writer.recordEvent("first", "{\"ok\":true}");
    try writer.recordEvent("second", "{\"ok\":true}");

    const path = try std.fs.path.join(allocator, &.{ dir, "events.jsonl" });
    defer allocator.free(path);
    const bytes = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
    defer allocator.free(bytes);

    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"kind\":\"first\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"kind\":\"second\"") != null);
    try std.testing.expect(std.mem.count(u8, bytes, "\n") == 2);
}

test "trace writer init resets stale events and artifacts" {
    const allocator = std.testing.allocator;
    const dir = "zig-cache-test-trace-reset";
    std.fs.cwd().deleteTree(dir) catch {};
    defer std.fs.cwd().deleteTree(dir) catch {};

    try std.fs.cwd().makePath(dir ++ "/artifacts");
    {
        var events = try std.fs.cwd().createFile(dir ++ "/events.jsonl", .{ .truncate = true });
        defer events.close();
        try events.writeAll("{\"seq\":99,\"kind\":\"stale\",\"payload\":{}}\n");
    }
    {
        var artifact = try std.fs.cwd().createFile(dir ++ "/artifacts/stale.png", .{ .truncate = true });
        defer artifact.close();
        try artifact.writeAll("stale");
    }

    var writer = try TraceWriter.init(allocator, dir);
    defer writer.deinit();

    try writer.recordEvent("fresh", "{\"ok\":true}");

    const events_path = try std.fs.path.join(allocator, &.{ dir, "events.jsonl" });
    defer allocator.free(events_path);
    const bytes = try std.fs.cwd().readFileAlloc(allocator, events_path, 1024 * 1024);
    defer allocator.free(bytes);

    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"kind\":\"stale\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"kind\":\"fresh\"") != null);
    try std.testing.expectError(error.FileNotFound, std.fs.cwd().access(dir ++ "/artifacts/stale.png", .{}));
}

test "trace writer writes and finalizes manifest" {
    const allocator = std.testing.allocator;
    const dir = "zig-cache-test-trace-manifest";
    std.fs.cwd().deleteTree(dir) catch {};
    defer std.fs.cwd().deleteTree(dir) catch {};

    var writer = try TraceWriter.init(allocator, dir);
    defer writer.deinit();

    try writer.startManifest("manifest flow", "com.example.mobiletest");
    try writer.recordEvent("scenario.start", "{\"value\":\"manifest flow\"}");
    try writer.finishManifest(.{
        .status = "passed",
        .report_path = "report.html",
    });

    const path = try std.fs.path.join(allocator, &.{ dir, "trace.json" });
    defer allocator.free(path);
    const bytes = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
    defer allocator.free(bytes);

    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"scenarioName\":\"manifest flow\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"appId\":\"com.example.mobiletest\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"status\":\"passed\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"eventsPath\":\"events.jsonl\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"artifactsDir\":\"artifacts\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"eventCount\":1") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"reportPath\":\"report.html\"") != null);
}

test "json string escapes quotes slashes and control characters" {
    const allocator = std.testing.allocator;
    var buffer = std.ArrayList(u8).empty;
    defer buffer.deinit(allocator);

    try writeJsonString(buffer.writer(allocator), "a\"b\\c\n\r\t\x01");
    try std.testing.expectEqualStrings("\"a\\\"b\\\\c\\n\\r\\t\\u0001\"", buffer.items);
}

test "raw snapshot json preserves text for live observations" {
    const allocator = std.testing.allocator;
    var node = types.UiNode{
        .stable_id = try allocator.dupe(u8, "node-email"),
        .class_name = try allocator.dupe(u8, "android.widget.EditText"),
        .text = try allocator.dupe(u8, "agent@example.com"),
    };
    defer node.deinit(allocator);
    const nodes = try allocator.alloc(types.UiNode, 1);
    defer allocator.free(nodes);
    nodes[0] = node;

    const snapshot = types.ObservationSnapshot{
        .id = try allocator.dupe(u8, "snapshot-live"),
        .timestamp_ms = 1,
        .nodes = nodes,
    };
    defer allocator.free(snapshot.id);

    var buffer = std.ArrayList(u8).empty;
    defer buffer.deinit(allocator);
    try writeSnapshotJson(buffer.writer(allocator), snapshot);

    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "agent@example.com") != null);
}

test "selector json emits every selector field in stable order" {
    const allocator = std.testing.allocator;
    var buffer = std.ArrayList(u8).empty;
    defer buffer.deinit(allocator);

    try writeSelectorJson(buffer.writer(allocator), .{
        .id = "login",
        .text = "Sign in",
        .text_contains = "Sign",
        .content_desc = "Primary action",
        .content_desc_contains = "Primary",
        .class_name = "android.widget.Button",
    });
    try std.testing.expectEqualStrings(
        "{\"id\":\"login\",\"text\":\"Sign in\",\"textContains\":\"Sign\",\"contentDesc\":\"Primary action\",\"contentDescContains\":\"Primary\",\"className\":\"android.widget.Button\"}",
        buffer.items,
    );
}

test "trace writer writes artifacts and full snapshot json" {
    const allocator = std.testing.allocator;
    const dir = "zig-cache-test-trace-snapshot";
    std.fs.cwd().deleteTree(dir) catch {};
    defer std.fs.cwd().deleteTree(dir) catch {};

    var writer = try TraceWriter.init(allocator, dir);
    defer writer.deinit();

    const next_id = try writer.nextSnapshotId();
    defer allocator.free(next_id);
    try std.testing.expectEqualStrings("snapshot-1", next_id);

    const artifact = try writer.writeArtifact("raw.txt", "payload");
    defer allocator.free(artifact);
    const artifact_bytes = try std.fs.cwd().readFileAlloc(allocator, artifact, 1024);
    defer allocator.free(artifact_bytes);
    try std.testing.expectEqualStrings("payload", artifact_bytes);

    var node = types.UiNode{
        .stable_id = try allocator.dupe(u8, "node-1"),
        .class_name = try allocator.dupe(u8, "android.widget.EditText"),
        .resource_id = try allocator.dupe(u8, "email"),
        .text = try allocator.dupe(u8, "agent@example.com"),
        .content_desc = try allocator.dupe(u8, "Email"),
        .bounds = .{ .x = 1, .y = 2, .width = 3, .height = 4 },
        .enabled = false,
        .visible = true,
        .selected = true,
    };
    defer node.deinit(allocator);
    const nodes = try allocator.alloc(types.UiNode, 1);
    defer allocator.free(nodes);
    nodes[0] = node;

    const snapshot = types.ObservationSnapshot{
        .id = try allocator.dupe(u8, "snapshot-file"),
        .timestamp_ms = 99,
        .viewport = .{ .width = 320, .height = 640 },
        .display_density_dpi = 420,
        .active_package = "com.example.mobiletest",
        .active_activity = ".MainActivity",
        .screenshot_artifact = "screen.png",
        .tree_artifact = "tree.xml",
        .focused_node_id = "node-1",
        .nodes = nodes,
    };
    defer allocator.free(snapshot.id);

    const path = try writer.writeSnapshot(snapshot);
    defer allocator.free(path);
    const bytes = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
    defer allocator.free(bytes);

    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"activePackage\":\"com.example.mobiletest\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"displayDensityDpi\":420") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"resourceId\":\"email\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"enabled\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "\"selected\":true") != null);
}

test "persisted snapshot json redacts sensitive text content and logs" {
    const allocator = std.testing.allocator;
    const jwt =
        "eyJhbGciOiJSUzI1NiIsImtpZCI6IjFiMjMifQ.eyJlbWFpbCI6ImFnZW50QGV4YW1wbGUuY29tIn0.signature";
    var node = types.UiNode{
        .stable_id = try allocator.dupe(u8, "node-secret"),
        .class_name = try allocator.dupe(u8, "android.widget.EditText"),
        .resource_id = try allocator.dupe(u8, "email-login-email-input"),
        .text = try allocator.dupe(u8, "agent@example.com"),
        .content_desc = try allocator.dupe(u8, "Bearer " ++ jwt),
    };
    defer node.deinit(allocator);
    const nodes = try allocator.alloc(types.UiNode, 1);
    defer allocator.free(nodes);
    nodes[0] = node;

    const snapshot = types.ObservationSnapshot{
        .id = try allocator.dupe(u8, "snapshot-secret"),
        .timestamp_ms = 1,
        .log_delta = try allocator.dupe(u8, "Authorization: Bearer " ++ jwt ++ "\nemail=agent@example.com"),
        .nodes = nodes,
    };
    defer {
        allocator.free(snapshot.id);
        allocator.free(snapshot.log_delta.?);
    }

    var buffer = std.ArrayList(u8).empty;
    defer buffer.deinit(allocator);
    try writeSnapshotJsonRedacted(buffer.writer(allocator), snapshot, .{});

    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "agent@example.com") == null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, jwt) == null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "[REDACTED:email]") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "[REDACTED:token]") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"logDelta\"") != null);
}

test "trace events redact nested secret payloads before writing" {
    const allocator = std.testing.allocator;
    const dir = "zig-cache-test-trace-redaction";
    std.fs.cwd().deleteTree(dir) catch {};
    defer std.fs.cwd().deleteTree(dir) catch {};

    var writer = try TraceWriter.init(allocator, dir);
    defer writer.deinit();

    try writer.recordEvent(
        "leaky",
        "{\"email\":\"agent@example.com\",\"auth\":{\"idToken\":\"secret-token-value\"},\"visibleTexts\":[\"hello\",\"agent@example.com\"]}",
    );

    const path = try std.fs.path.join(allocator, &.{ dir, "events.jsonl" });
    defer allocator.free(path);
    const bytes = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
    defer allocator.free(bytes);

    try std.testing.expect(std.mem.indexOf(u8, bytes, "agent@example.com") == null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "secret-token-value") == null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "[REDACTED:email]") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "[REDACTED:secret]") != null);
}

test "trace writer applies app-specific redaction rules to snapshots and events" {
    const allocator = std.testing.allocator;
    const dir = "zig-cache-test-trace-custom-redaction";
    std.fs.cwd().deleteTree(dir) catch {};
    defer std.fs.cwd().deleteTree(dir) catch {};

    var writer = try TraceWriter.initWithOptions(allocator, dir, .{
        .redaction = .{
            .denylist_text = &.{ "customer dob", "internal token" },
            .allowlist_text = &.{"public token label"},
            .denylist_resource_ids = &.{"password-field"},
            .allowlist_resource_ids = &.{"public-token-label"},
        },
    });
    defer writer.deinit();

    var sensitive_node = types.UiNode{
        .stable_id = try allocator.dupe(u8, "node-sensitive"),
        .class_name = try allocator.dupe(u8, "android.widget.EditText"),
        .resource_id = try allocator.dupe(u8, "login-password-field"),
        .text = try allocator.dupe(u8, "Customer DOB 1990-01-01"),
        .content_desc = try allocator.dupe(u8, "Internal token field"),
    };
    defer sensitive_node.deinit(allocator);
    var public_node = types.UiNode{
        .stable_id = try allocator.dupe(u8, "node-public"),
        .class_name = try allocator.dupe(u8, "android.widget.TextView"),
        .resource_id = try allocator.dupe(u8, "public-token-label"),
        .text = try allocator.dupe(u8, "Public token label"),
    };
    defer public_node.deinit(allocator);
    const nodes = try allocator.alloc(types.UiNode, 2);
    defer allocator.free(nodes);
    nodes[0] = sensitive_node;
    nodes[1] = public_node;

    const snapshot = types.ObservationSnapshot{
        .id = try allocator.dupe(u8, "snapshot-custom-redaction"),
        .timestamp_ms = 1,
        .log_delta = try allocator.dupe(u8, "debug Customer DOB 1990-01-01"),
        .nodes = nodes,
    };
    defer {
        allocator.free(snapshot.id);
        allocator.free(snapshot.log_delta.?);
    }

    const snapshot_path = try writer.writeSnapshot(snapshot);
    defer allocator.free(snapshot_path);
    try writer.recordEvent("custom", "{\"note\":\"internal token abc\",\"label\":\"Public token label\"}");

    const snapshot_bytes = try std.fs.cwd().readFileAlloc(allocator, snapshot_path, 1024 * 1024);
    defer allocator.free(snapshot_bytes);
    const events_path = try std.fs.path.join(allocator, &.{ dir, "events.jsonl" });
    defer allocator.free(events_path);
    const event_bytes = try std.fs.cwd().readFileAlloc(allocator, events_path, 1024 * 1024);
    defer allocator.free(event_bytes);

    try std.testing.expect(std.mem.indexOf(u8, snapshot_bytes, "Customer DOB 1990-01-01") == null);
    try std.testing.expect(std.mem.indexOf(u8, snapshot_bytes, "Internal token field") == null);
    try std.testing.expect(std.mem.indexOf(u8, snapshot_bytes, "login-password-field") == null);
    try std.testing.expect(std.mem.indexOf(u8, snapshot_bytes, "\"resourceId\":\"[REDACTED:resourceId]\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, snapshot_bytes, "\"resourceId\":\"public-token-label\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, snapshot_bytes, "Public token label") != null);
    try std.testing.expect(std.mem.indexOf(u8, snapshot_bytes, "[REDACTED:custom]") != null);

    try std.testing.expect(std.mem.indexOf(u8, event_bytes, "internal token abc") == null);
    try std.testing.expect(std.mem.indexOf(u8, event_bytes, "Public token label") != null);
    try std.testing.expect(std.mem.indexOf(u8, event_bytes, "[REDACTED:custom]") != null);
}
