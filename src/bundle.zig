const std = @import("std");

pub const ExportOptions = struct {
    redact: bool = false,
    omit_screenshots: bool = false,
};

pub fn exportTraceBundle(allocator: std.mem.Allocator, trace_dir: []const u8, out_path: []const u8) !void {
    return exportTraceBundleWithOptions(allocator, trace_dir, out_path, .{});
}

pub fn exportTraceBundleWithOptions(
    allocator: std.mem.Allocator,
    trace_dir: []const u8,
    out_path: []const u8,
    options: ExportOptions,
) !void {
    try requireTraceFile(allocator, trace_dir, "trace.json", error.MissingTraceManifest);
    try requireTraceFile(allocator, trace_dir, "events.jsonl", error.MissingTraceEvents);

    var entries = std.ArrayList([]const u8).empty;
    defer {
        for (entries.items) |entry| allocator.free(entry);
        entries.deinit(allocator);
    }

    try entries.append(allocator, try allocator.dupe(u8, "trace.json"));
    try entries.append(allocator, try allocator.dupe(u8, "events.jsonl"));
    if (traceFileExists(allocator, trace_dir, "report.html") catch |err| return err) {
        try entries.append(allocator, try allocator.dupe(u8, "report.html"));
    }

    var artifact_entries = std.ArrayList([]const u8).empty;
    defer {
        for (artifact_entries.items) |entry| allocator.free(entry);
        artifact_entries.deinit(allocator);
    }
    try collectArtifactEntries(allocator, trace_dir, "artifacts", &artifact_entries);
    std.mem.sort([]const u8, artifact_entries.items, {}, stringLessThan);
    for (artifact_entries.items) |entry| {
        try entries.append(allocator, try allocator.dupe(u8, entry));
    }

    var out_file = try std.fs.cwd().createFile(out_path, .{ .truncate = true });
    defer out_file.close();

    for (entries.items) |archive_path| {
        if (options.redact) {
            if (options.omit_screenshots and isScreenshotPath(archive_path)) continue;
            if (isPlaceholderScreenshotPath(archive_path)) {
                try writeTarBytes(archive_path, redacted_screenshot_png[0..], &out_file);
                continue;
            }
            if (isVisualArtifactPath(archive_path)) continue;
            const bytes = try readTraceFile(allocator, trace_dir, archive_path);
            defer allocator.free(bytes);
            const redacted = try redactEntry(allocator, archive_path, bytes, options);
            defer allocator.free(redacted);
            try writeTarBytes(archive_path, redacted, &out_file);
        } else {
            try writeTarFile(allocator, trace_dir, archive_path, &out_file);
        }
    }
    try out_file.writeAll(&([_]u8{0} ** 1024));
}

fn requireTraceFile(
    allocator: std.mem.Allocator,
    trace_dir: []const u8,
    archive_path: []const u8,
    missing_error: anyerror,
) !void {
    if (!try traceFileExists(allocator, trace_dir, archive_path)) return missing_error;
}

fn traceFileExists(allocator: std.mem.Allocator, trace_dir: []const u8, archive_path: []const u8) !bool {
    const path = try std.fs.path.join(allocator, &.{ trace_dir, archive_path });
    defer allocator.free(path);
    const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    file.close();
    return true;
}

fn readTraceFile(allocator: std.mem.Allocator, trace_dir: []const u8, archive_path: []const u8) ![]u8 {
    const path = try std.fs.path.join(allocator, &.{ trace_dir, archive_path });
    defer allocator.free(path);
    return try std.fs.cwd().readFileAlloc(allocator, path, 64 * 1024 * 1024);
}

fn collectArtifactEntries(
    allocator: std.mem.Allocator,
    trace_dir: []const u8,
    archive_dir: []const u8,
    entries: *std.ArrayList([]const u8),
) !void {
    const fs_dir = try std.fs.path.join(allocator, &.{ trace_dir, archive_dir });
    defer allocator.free(fs_dir);

    var dir = std.fs.cwd().openDir(fs_dir, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer dir.close();

    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        const archive_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ archive_dir, entry.name });
        errdefer allocator.free(archive_path);
        switch (entry.kind) {
            .file => try entries.append(allocator, archive_path),
            .directory => {
                try collectArtifactEntries(allocator, trace_dir, archive_path, entries);
                allocator.free(archive_path);
            },
            else => allocator.free(archive_path),
        }
    }
}

fn stringLessThan(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

fn writeTarFile(
    allocator: std.mem.Allocator,
    trace_dir: []const u8,
    archive_path: []const u8,
    out_file: *std.fs.File,
) !void {
    if (std.mem.startsWith(u8, archive_path, "/") or std.mem.indexOf(u8, archive_path, "..") != null) {
        return error.UnsafeArchivePath;
    }
    const fs_path = try std.fs.path.join(allocator, &.{ trace_dir, archive_path });
    defer allocator.free(fs_path);

    var in_file = try std.fs.cwd().openFile(fs_path, .{});
    defer in_file.close();
    const stat = try in_file.stat();

    var header = [_]u8{0} ** 512;
    try writeTarName(&header, archive_path);
    writeOctal(header[100..108], 0o644);
    writeOctal(header[108..116], 0);
    writeOctal(header[116..124], 0);
    writeOctal(header[124..136], stat.size);
    writeOctal(header[136..148], 0);
    @memset(header[148..156], ' ');
    header[156] = '0';
    @memcpy(header[257..263], "ustar\x00");
    @memcpy(header[263..265], "00");
    writeOctal(header[329..337], 0);
    writeOctal(header[337..345], 0);
    const checksum = tarChecksum(&header);
    writeChecksum(header[148..156], checksum);

    try out_file.writeAll(&header);
    var buffer: [16 * 1024]u8 = undefined;
    var remaining = stat.size;
    while (remaining > 0) {
        const read_len = @min(buffer.len, remaining);
        const n = try in_file.read(buffer[0..read_len]);
        if (n == 0) return error.UnexpectedEndOfStream;
        try out_file.writeAll(buffer[0..n]);
        remaining -= n;
    }
    const padding = (512 - (stat.size % 512)) % 512;
    if (padding > 0) try out_file.writeAll((&([_]u8{0} ** 512))[0..padding]);
}

fn writeTarBytes(archive_path: []const u8, bytes: []const u8, out_file: *std.fs.File) !void {
    if (std.mem.startsWith(u8, archive_path, "/") or std.mem.indexOf(u8, archive_path, "..") != null) {
        return error.UnsafeArchivePath;
    }
    var header = [_]u8{0} ** 512;
    try writeTarName(&header, archive_path);
    writeOctal(header[100..108], 0o644);
    writeOctal(header[108..116], 0);
    writeOctal(header[116..124], 0);
    writeOctal(header[124..136], bytes.len);
    writeOctal(header[136..148], 0);
    @memset(header[148..156], ' ');
    header[156] = '0';
    @memcpy(header[257..263], "ustar\x00");
    @memcpy(header[263..265], "00");
    writeOctal(header[329..337], 0);
    writeOctal(header[337..345], 0);
    const checksum = tarChecksum(&header);
    writeChecksum(header[148..156], checksum);

    try out_file.writeAll(&header);
    try out_file.writeAll(bytes);
    const padding = (512 - (bytes.len % 512)) % 512;
    if (padding > 0) try out_file.writeAll((&([_]u8{0} ** 512))[0..padding]);
}

fn redactEntry(allocator: std.mem.Allocator, archive_path: []const u8, bytes: []const u8, options: ExportOptions) ![]u8 {
    if (std.mem.eql(u8, archive_path, "trace.json")) {
        return try redactTraceManifest(allocator, bytes, options);
    }
    if (std.mem.endsWith(u8, archive_path, ".json") or std.mem.eql(u8, archive_path, "events.jsonl")) {
        return redactJsonishText(allocator, bytes);
    }
    if (isTextPath(archive_path)) {
        return redactFreeText(allocator, bytes);
    }
    return try allocator.dupe(u8, bytes);
}

fn redactTraceManifest(allocator: std.mem.Allocator, bytes: []const u8, options: ExportOptions) ![]u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, bytes, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return try redactJsonishText(allocator, bytes);

    const arena_allocator = parsed.arena.allocator();
    var redaction = std.json.ObjectMap.init(arena_allocator);
    try redaction.put("enabled", .{ .bool = true });
    try redaction.put("screenshots", .{ .string = if (options.omit_screenshots) "omitted" else "placeholder" });
    try redaction.put("screenRecordings", .{ .string = "omitted" });
    try redaction.put("textArtifacts", .{ .string = "scrubbed" });
    try redaction.put("screenshotsOmitted", .{ .bool = options.omit_screenshots });
    try redaction.put("screenshotsRedacted", .{ .bool = !options.omit_screenshots });
    try redaction.put("screenRecordingsOmitted", .{ .bool = true });
    try parsed.value.object.put("redaction", .{ .object = redaction });

    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try writeJsonValueRedacted(out.writer(allocator), parsed.value, null);
    try out.writer(allocator).writeByte('\n');
    return try out.toOwnedSlice(allocator);
}

fn redactJsonishText(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, bytes, .{}) catch {
        return redactFreeText(allocator, bytes);
    };
    defer parsed.deinit();
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try writeJsonValueRedacted(out.writer(allocator), parsed.value, null);
    try out.writer(allocator).writeByte('\n');
    return try out.toOwnedSlice(allocator);
}

fn writeJsonValueRedacted(writer: anytype, value: std.json.Value, key_context: ?[]const u8) !void {
    switch (value) {
        .null => try writer.writeAll("null"),
        .bool => |actual| try writer.writeAll(if (actual) "true" else "false"),
        .integer => |actual| try writer.print("{d}", .{actual}),
        .float => |actual| try writer.print("{d}", .{actual}),
        .number_string => |actual| try writer.writeAll(actual),
        .string => |actual| try writeRedactedJsonStringForKey(writer, key_context orelse "", actual),
        .array => |array| {
            try writer.writeAll("[");
            for (array.items, 0..) |item, index| {
                if (index > 0) try writer.writeAll(",");
                try writeJsonValueRedacted(writer, item, key_context);
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
                try writeJsonValueRedacted(writer, entry.value_ptr.*, entry.key_ptr.*);
            }
            try writer.writeAll("}");
        },
    }
}

fn writeRedactedJsonStringForKey(writer: anytype, key: []const u8, value: []const u8) !void {
    if (isSensitiveLabel(key)) {
        try writeJsonString(writer, "[REDACTED:secret]");
    } else if (looksLikeBearerOrToken(value)) {
        try writeJsonString(writer, "[REDACTED:token]");
    } else if (looksLikeEmail(value)) {
        try writeJsonString(writer, "[REDACTED:email]");
    } else {
        try writeJsonString(writer, value);
    }
}

fn redactFreeText(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    var sensitive_tag = false;
    var index: usize = 0;
    while (index < bytes.len) {
        if (bytes[index] == '<') {
            sensitive_tag = tagLooksSensitive(bytes[index..@min(bytes.len, index + 240)]);
        } else if (bytes[index] == '>') {
            sensitive_tag = false;
        }

        if (sensitive_tag and (startsWithAt(bytes, index, "text=\"") or startsWithAt(bytes, index, "content-desc=\""))) {
            const prefix_len: usize = if (startsWithAt(bytes, index, "text=\"")) 6 else 14;
            try out.writer(allocator).writeAll(bytes[index .. index + prefix_len]);
            try out.writer(allocator).writeAll("[REDACTED:secret]");
            index += prefix_len;
            while (index < bytes.len and bytes[index] != '"') : (index += 1) {}
            if (index < bytes.len) {
                try out.writer(allocator).writeByte('"');
                index += 1;
            }
            continue;
        }

        if (emailEnd(bytes, index)) |end| {
            try out.writer(allocator).writeAll("[REDACTED:email]");
            index = end;
            continue;
        }
        if (bearerEnd(bytes, index)) |end| {
            try out.writer(allocator).writeAll("[REDACTED:token]");
            index = end;
            continue;
        }
        try out.writer(allocator).writeByte(bytes[index]);
        index += 1;
    }
    return try out.toOwnedSlice(allocator);
}

fn emailEnd(bytes: []const u8, start: usize) ?usize {
    if (start > 0 and !isDelimiter(bytes[start - 1])) return null;
    var end = start;
    while (end < bytes.len and !isDelimiter(bytes[end])) : (end += 1) {}
    const value = bytes[start..end];
    return if (looksLikeEmail(value)) end else null;
}

fn bearerEnd(bytes: []const u8, start: usize) ?usize {
    if (!startsWithIgnoreCase(bytes[start..], "bearer ")) return null;
    var end = start;
    while (end < bytes.len and bytes[end] != '"' and bytes[end] != '\'' and bytes[end] != '<' and bytes[end] != '>') : (end += 1) {}
    return end;
}

fn tagLooksSensitive(bytes: []const u8) bool {
    const end = std.mem.indexOfScalar(u8, bytes, '>') orelse bytes.len;
    return isSensitiveLabel(bytes[0..end]);
}

fn isScreenshotPath(path: []const u8) bool {
    return std.mem.endsWith(u8, path, ".png") or std.mem.endsWith(u8, path, ".jpg") or std.mem.endsWith(u8, path, ".jpeg");
}

fn isPlaceholderScreenshotPath(path: []const u8) bool {
    return std.mem.endsWith(u8, path, ".png");
}

fn isVisualArtifactPath(path: []const u8) bool {
    return isScreenshotPath(path) or std.mem.endsWith(u8, path, ".mp4") or std.mem.endsWith(u8, path, ".webm");
}

const redacted_screenshot_png = [_]u8{
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
    0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4,
    0x89, 0x00, 0x00, 0x00, 0x0a, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00,
    0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae,
    0x42, 0x60, 0x82,
};

fn isTextPath(path: []const u8) bool {
    return std.mem.endsWith(u8, path, ".xml") or std.mem.endsWith(u8, path, ".html") or std.mem.endsWith(u8, path, ".txt") or std.mem.endsWith(u8, path, ".log");
}

fn writeTarName(header: *[512]u8, archive_path: []const u8) !void {
    if (archive_path.len <= 100) {
        @memcpy(header[0..archive_path.len], archive_path);
        return;
    }

    var split_index: ?usize = null;
    var index: usize = archive_path.len;
    while (index > 0) {
        index -= 1;
        if (archive_path[index] != '/') continue;
        const prefix = archive_path[0..index];
        const name = archive_path[index + 1 ..];
        if (prefix.len <= 155 and name.len <= 100) {
            split_index = index;
            break;
        }
    }
    const actual_split = split_index orelse return error.ArchivePathTooLong;
    const prefix = archive_path[0..actual_split];
    const name = archive_path[actual_split + 1 ..];
    @memcpy(header[0..name.len], name);
    @memcpy(header[345 .. 345 + prefix.len], prefix);
}

fn writeOctal(field: []u8, value: u64) void {
    @memset(field, 0);
    const digits_len = field.len - 1;
    var remaining = value;
    var index = digits_len;
    while (index > 0) {
        index -= 1;
        field[index] = @as(u8, @intCast('0' + (remaining & 7)));
        remaining >>= 3;
    }
}

fn writeChecksum(field: []u8, value: u64) void {
    @memset(field, 0);
    var remaining = value;
    var index: usize = 6;
    while (index > 0) {
        index -= 1;
        field[index] = @as(u8, @intCast('0' + (remaining & 7)));
        remaining >>= 3;
    }
    field[6] = 0;
    field[7] = ' ';
}

fn tarChecksum(header: *const [512]u8) u64 {
    var sum: u64 = 0;
    for (header) |byte| sum += byte;
    return sum;
}

fn writeJsonString(writer: anytype, value: []const u8) !void {
    try writer.writeAll("\"");
    for (value) |ch| {
        switch (ch) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            0...7, 11, 12, 14...31 => try writer.print("\\u{x:0>4}", .{ch}),
            else => try writer.writeByte(ch),
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

fn looksLikeEmail(value: []const u8) bool {
    if (value.len < 5 or value.len > 254) return false;
    if (std.mem.indexOfAny(u8, value, " \t\r\n<>\"'") != null) return false;
    const at = std.mem.indexOfScalar(u8, value, '@') orelse return false;
    if (at == 0 or at + 3 >= value.len) return false;
    return std.mem.indexOfScalar(u8, value[at + 1 ..], '.') != null;
}

fn looksLikeBearerOrToken(value: []const u8) bool {
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

fn startsWithAt(bytes: []const u8, index: usize, needle: []const u8) bool {
    return index + needle.len <= bytes.len and std.mem.eql(u8, bytes[index .. index + needle.len], needle);
}

fn startsWithIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    for (needle, 0..) |needle_ch, index| {
        if (std.ascii.toLower(haystack[index]) != std.ascii.toLower(needle_ch)) return false;
    }
    return true;
}

fn isDelimiter(ch: u8) bool {
    return switch (ch) {
        ' ', '\t', '\r', '\n', '<', '>', '"', '\'', '=', ',', ';', ')' => true,
        else => false,
    };
}

test "trace bundle export writes deterministic archive with manifest events report and artifacts" {
    const allocator = std.testing.allocator;
    const root = "zig-cache-test-trace-bundle";
    const out_path = root ++ ".zmrtrace";
    defer std.fs.cwd().deleteTree(root) catch {};
    defer std.fs.cwd().deleteFile(out_path) catch {};
    try std.fs.cwd().makePath(root ++ "/artifacts");
    try writeFixture(root ++ "/trace.json", "{\"schemaVersion\":1,\"status\":\"passed\"}\n");
    try writeFixture(root ++ "/events.jsonl", "{\"seq\":1,\"kind\":\"scenario.end\",\"payload\":{\"status\":\"passed\"}}\n");
    try writeFixture(root ++ "/report.html", "<!doctype html><h1>ZMR</h1>\n");
    try writeFixture(root ++ "/artifacts/snapshot-1.json", "{\"id\":\"snapshot-1\"}\n");
    try writeFixture(root ++ "/artifacts/snapshot-1.xml", "<hierarchy />\n");

    try exportTraceBundle(allocator, root, out_path);

    const archive = try std.fs.cwd().readFileAlloc(allocator, out_path, 1024 * 1024);
    defer allocator.free(archive);
    const names = try tarNames(allocator, archive);
    defer {
        for (names) |name| allocator.free(name);
        allocator.free(names);
    }

    try std.testing.expectEqual(@as(usize, 5), names.len);
    try std.testing.expectEqualStrings("trace.json", names[0]);
    try std.testing.expectEqualStrings("events.jsonl", names[1]);
    try std.testing.expectEqualStrings("report.html", names[2]);
    try std.testing.expectEqualStrings("artifacts/snapshot-1.json", names[3]);
    try std.testing.expectEqualStrings("artifacts/snapshot-1.xml", names[4]);
    try std.testing.expect(std.mem.indexOf(u8, archive, "snapshot-1") != null);
}

test "trace bundle export rejects directories without a manifest" {
    const allocator = std.testing.allocator;
    const root = "zig-cache-test-trace-bundle-missing";
    const out_path = root ++ ".zmrtrace";
    defer std.fs.cwd().deleteTree(root) catch {};
    defer std.fs.cwd().deleteFile(out_path) catch {};
    try std.fs.cwd().makePath(root);
    try writeFixture(root ++ "/events.jsonl", "{}\n");

    try std.testing.expectError(error.MissingTraceManifest, exportTraceBundle(allocator, root, out_path));
}

test "redacted trace bundle replaces screenshots scrubs text artifacts and annotates manifest" {
    const allocator = std.testing.allocator;
    const root = "zig-cache-test-trace-bundle-redacted";
    const out_path = root ++ ".zmrtrace";
    defer std.fs.cwd().deleteTree(root) catch {};
    defer std.fs.cwd().deleteFile(out_path) catch {};
    try std.fs.cwd().makePath(root ++ "/artifacts");
    try writeFixture(root ++ "/trace.json", "{\"schemaVersion\":1,\"status\":\"failed\",\"eventsPath\":\"events.jsonl\",\"artifactsDir\":\"artifacts\"}\n");
    try writeFixture(root ++ "/events.jsonl", "{\"seq\":1,\"kind\":\"log\",\"payload\":{\"message\":\"agent@example.com bearer abc.def.ghi\"}}\n");
    try writeFixture(
        root ++ "/artifacts/snapshot-1.xml",
        "<node resource-id=\"password-field\" text=\"hunter2\" content-desc=\"agent@example.com\" /><node text=\"Bearer abc.def.ghi\" />\n",
    );
    try writeFixture(
        root ++ "/artifacts/snapshot-1.json",
        "{\"id\":\"snapshot-1\",\"text\":\"agent@example.com\",\"authToken\":\"abc.def.ghi\"}\n",
    );
    try writeFixture(root ++ "/artifacts/snapshot-1.png", "agent@example.com image bytes");
    try writeFixture(root ++ "/artifacts/screenrecord.mp4", "agent@example.com video bytes");

    try exportTraceBundleWithOptions(allocator, root, out_path, .{ .redact = true });

    const archive = try std.fs.cwd().readFileAlloc(allocator, out_path, 1024 * 1024);
    defer allocator.free(archive);
    const names = try tarNames(allocator, archive);
    defer {
        for (names) |name| allocator.free(name);
        allocator.free(names);
    }

    try std.testing.expectEqual(@as(usize, 5), names.len);
    try std.testing.expectEqualStrings("trace.json", names[0]);
    try std.testing.expectEqualStrings("events.jsonl", names[1]);
    try std.testing.expectEqualStrings("artifacts/snapshot-1.json", names[2]);
    try std.testing.expectEqualStrings("artifacts/snapshot-1.png", names[3]);
    try std.testing.expectEqualStrings("artifacts/snapshot-1.xml", names[4]);
    try std.testing.expect(std.mem.indexOf(u8, archive, "redaction") != null);
    try std.testing.expect(std.mem.indexOf(u8, archive, "screenshotsOmitted") != null);
    try std.testing.expect(std.mem.indexOf(u8, archive, "screenshotsRedacted") != null);
    try std.testing.expect(std.mem.indexOf(u8, archive, "screenRecordingsOmitted") != null);
    try std.testing.expect(std.mem.indexOf(u8, archive, "\x89PNG\r\n\x1a\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, archive, "image bytes") == null);
    try std.testing.expect(std.mem.indexOf(u8, archive, "video bytes") == null);
    try std.testing.expect(std.mem.indexOf(u8, archive, "agent@example.com") == null);
    try std.testing.expect(std.mem.indexOf(u8, archive, "hunter2") == null);
    try std.testing.expect(std.mem.indexOf(u8, archive, "Bearer abc.def.ghi") == null);
    try std.testing.expect(std.mem.indexOf(u8, archive, "authToken") != null);
    try std.testing.expect(std.mem.indexOf(u8, archive, "[REDACTED") != null);
}

test "redacted trace bundle can omit screenshots entirely" {
    const allocator = std.testing.allocator;
    const root = "zig-cache-test-trace-bundle-redacted-omit-screenshots";
    const out_path = root ++ ".zmrtrace";
    defer std.fs.cwd().deleteTree(root) catch {};
    defer std.fs.cwd().deleteFile(out_path) catch {};
    try std.fs.cwd().makePath(root ++ "/artifacts");
    try writeFixture(root ++ "/trace.json", "{\"schemaVersion\":1,\"status\":\"passed\",\"eventsPath\":\"events.jsonl\",\"artifactsDir\":\"artifacts\"}\n");
    try writeFixture(root ++ "/events.jsonl", "{\"seq\":1,\"kind\":\"scenario.end\",\"payload\":{\"status\":\"passed\"}}\n");
    try writeFixture(root ++ "/artifacts/snapshot-1.json", "{\"id\":\"snapshot-1\",\"text\":\"agent@example.com\"}\n");
    try writeFixture(root ++ "/artifacts/snapshot-1.png", "private screenshot bytes");

    try exportTraceBundleWithOptions(allocator, root, out_path, .{ .redact = true, .omit_screenshots = true });

    const archive = try std.fs.cwd().readFileAlloc(allocator, out_path, 1024 * 1024);
    defer allocator.free(archive);
    const names = try tarNames(allocator, archive);
    defer {
        for (names) |name| allocator.free(name);
        allocator.free(names);
    }

    try std.testing.expectEqual(@as(usize, 3), names.len);
    try std.testing.expectEqualStrings("trace.json", names[0]);
    try std.testing.expectEqualStrings("events.jsonl", names[1]);
    try std.testing.expectEqualStrings("artifacts/snapshot-1.json", names[2]);
    try std.testing.expect(std.mem.indexOf(u8, archive, "private screenshot bytes") == null);
    try std.testing.expect(std.mem.indexOf(u8, archive, "\x89PNG\r\n\x1a\n") == null);
    try std.testing.expect(std.mem.indexOf(u8, archive, "\"screenshots\":\"omitted\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, archive, "\"screenshotsOmitted\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, archive, "\"screenshotsRedacted\":false") != null);
}

fn writeFixture(path: []const u8, bytes: []const u8) !void {
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(bytes);
}

fn tarNames(allocator: std.mem.Allocator, archive: []const u8) ![][]const u8 {
    var names = std.ArrayList([]const u8).empty;
    errdefer {
        for (names.items) |name| allocator.free(name);
        names.deinit(allocator);
    }

    var offset: usize = 0;
    while (offset + 512 <= archive.len) {
        const header = archive[offset .. offset + 512];
        if (allZero(header)) break;
        const raw_name = std.mem.sliceTo(header[0..100], 0);
        const size_field = std.mem.trim(u8, header[124..136], " \x00");
        const size = try std.fmt.parseInt(usize, size_field, 8);
        try names.append(allocator, try allocator.dupe(u8, raw_name));
        offset += 512 + std.mem.alignForward(usize, size, 512);
    }

    return try names.toOwnedSlice(allocator);
}

fn allZero(bytes: []const u8) bool {
    for (bytes) |byte| if (byte != 0) return false;
    return true;
}
