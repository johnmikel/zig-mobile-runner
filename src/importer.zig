const std = @import("std");
const trace = @import("trace.zig");

pub const ImportOptions = struct {
    name: ?[]const u8 = null,
    app_id: ?[]const u8 = null,
    force: bool = false,
};

pub const ImportResult = struct {
    out_path: []const u8,
    name: []const u8,
    app_id: ?[]const u8,
    step_count: usize,

    pub fn deinit(self: ImportResult, allocator: std.mem.Allocator) void {
        allocator.free(self.out_path);
        allocator.free(self.name);
        if (self.app_id) |value| allocator.free(value);
    }
};

const ImportedScenario = struct {
    name: []const u8,
    app_id: ?[]const u8 = null,
    steps: []ImportedStep,

    fn deinit(self: ImportedScenario, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.app_id) |value| allocator.free(value);
        for (self.steps) |step| step.deinit(allocator);
        allocator.free(self.steps);
    }
};

const SelectorSpec = struct {
    id: ?[]const u8 = null,
    text: ?[]const u8 = null,
    text_contains: ?[]const u8 = null,
    content_desc: ?[]const u8 = null,

    fn deinit(self: SelectorSpec, allocator: std.mem.Allocator) void {
        if (self.id) |value| allocator.free(value);
        if (self.text) |value| allocator.free(value);
        if (self.text_contains) |value| allocator.free(value);
        if (self.content_desc) |value| allocator.free(value);
    }

    fn hasAny(self: SelectorSpec) bool {
        return self.id != null or self.text != null or self.text_contains != null or self.content_desc != null;
    }
};

const WaitSelector = struct {
    selector: SelectorSpec,
    timeout_ms: u64 = 5000,

    fn deinit(self: WaitSelector, allocator: std.mem.Allocator) void {
        self.selector.deinit(allocator);
    }
};

const ScrollStep = struct {
    selector: SelectorSpec,
    direction: []const u8 = "down",
    timeout_ms: u64 = 5000,

    fn deinit(self: ScrollStep, allocator: std.mem.Allocator) void {
        self.selector.deinit(allocator);
    }
};

const ImportedStep = union(enum) {
    launch,
    stop,
    clear_state,
    snapshot,
    hide_keyboard,
    press_back,
    open_link: []const u8,
    tap: SelectorSpec,
    type_text: []const u8,
    erase_text: u32,
    assert_visible: SelectorSpec,
    assert_not_visible: SelectorSpec,
    wait_visible: WaitSelector,
    wait_not_visible: WaitSelector,
    scroll_until_visible: ScrollStep,
    sleep_ms: u64,

    fn deinit(self: ImportedStep, allocator: std.mem.Allocator) void {
        switch (self) {
            .open_link => |value| allocator.free(value),
            .tap => |value| value.deinit(allocator),
            .type_text => |value| allocator.free(value),
            .assert_visible => |value| value.deinit(allocator),
            .assert_not_visible => |value| value.deinit(allocator),
            .wait_visible => |value| value.deinit(allocator),
            .wait_not_visible => |value| value.deinit(allocator),
            .scroll_until_visible => |value| value.deinit(allocator),
            else => {},
        }
    }
};

pub fn importFlowYamlFile(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    out_path: []const u8,
    options: ImportOptions,
) !ImportResult {
    if (!options.force and fileExists(out_path)) return error.ImportOutputExists;

    const content = try std.fs.cwd().readFileAlloc(allocator, source_path, 4 * 1024 * 1024);
    defer allocator.free(content);

    var imported = try parseFlowYamlSlice(allocator, content, options);
    defer imported.deinit(allocator);

    if (std.fs.path.dirname(out_path)) |dir| {
        if (dir.len > 0) try std.fs.cwd().makePath(dir);
    }

    var file = try std.fs.cwd().createFile(out_path, .{ .truncate = true });
    defer file.close();
    var write_buffer: [8192]u8 = undefined;
    var file_writer = file.writer(&write_buffer);
    try writeScenarioJson(&file_writer.interface, imported);
    try file_writer.interface.flush();

    return .{
        .out_path = try allocator.dupe(u8, out_path),
        .name = try allocator.dupe(u8, imported.name),
        .app_id = try dupeOptional(allocator, imported.app_id),
        .step_count = imported.steps.len,
    };
}

fn fileExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

fn parseFlowYamlSlice(allocator: std.mem.Allocator, content: []const u8, options: ImportOptions) !ImportedScenario {
    var header_app_id: ?[]const u8 = null;
    defer if (header_app_id) |value| allocator.free(value);
    var header_name: ?[]const u8 = null;
    defer if (header_name) |value| allocator.free(value);

    var steps = std.ArrayList(ImportedStep).empty;
    errdefer {
        for (steps.items) |step| step.deinit(allocator);
        steps.deinit(allocator);
    }

    var lines = std.ArrayList([]const u8).empty;
    defer lines.deinit(allocator);
    var split = std.mem.splitScalar(u8, content, '\n');
    while (split.next()) |line| {
        try lines.append(allocator, std.mem.trimRight(u8, line, "\r"));
    }

    var in_commands = false;
    var index: usize = 0;
    while (index < lines.items.len) {
        const raw = lines.items[index];
        const trimmed = trim(raw);
        if (trimmed.len == 0 or std.mem.startsWith(u8, trimmed, "#")) {
            index += 1;
            continue;
        }
        if (std.mem.eql(u8, trimmed, "---")) {
            in_commands = true;
            index += 1;
            continue;
        }
        if (!in_commands and !std.mem.startsWith(u8, trimmed, "- ")) {
            if (splitColon(trimmed)) |pair| {
                if (std.mem.eql(u8, pair.key, "appId")) {
                    if (header_app_id) |value| allocator.free(value);
                    header_app_id = try parseScalarString(allocator, pair.value);
                } else if (std.mem.eql(u8, pair.key, "name")) {
                    if (header_name) |value| allocator.free(value);
                    header_name = try parseScalarString(allocator, pair.value);
                }
            }
            index += 1;
            continue;
        }

        in_commands = true;
        if (!std.mem.startsWith(u8, trimmed, "- ")) return error.ImportExpectedCommand;
        const item = trim(trimmed[2..]);
        index += 1;
        const block_start = index;
        while (index < lines.items.len) : (index += 1) {
            const next = trim(lines.items[index]);
            if (std.mem.startsWith(u8, next, "- ") or std.mem.eql(u8, next, "---")) break;
        }
        try steps.append(allocator, try parseFlowYamlCommand(allocator, item, lines.items[block_start..index]));
    }

    const name = if (options.name) |value|
        try allocator.dupe(u8, value)
    else if (header_name) |value|
        try allocator.dupe(u8, value)
    else
        try allocator.dupe(u8, "Imported mobile flow");
    errdefer allocator.free(name);

    const app_id = if (options.app_id) |value|
        try allocator.dupe(u8, value)
    else
        try dupeOptional(allocator, header_app_id);
    errdefer if (app_id) |value| allocator.free(value);

    return .{
        .name = name,
        .app_id = app_id,
        .steps = try steps.toOwnedSlice(allocator),
    };
}

fn parseFlowYamlCommand(allocator: std.mem.Allocator, item: []const u8, block: []const []const u8) !ImportedStep {
    if (item.len == 0) return error.ImportExpectedCommand;
    if (splitColon(item)) |pair| {
        return try parseFlowYamlCommandWithValue(allocator, pair.key, pair.value, block);
    }
    if (std.mem.eql(u8, item, "launchApp")) return .launch;
    if (std.mem.eql(u8, item, "stopApp")) return .stop;
    if (std.mem.eql(u8, item, "clearState") or std.mem.eql(u8, item, "clearAppState")) return .clear_state;
    if (std.mem.eql(u8, item, "hideKeyboard")) return .hide_keyboard;
    if (std.mem.eql(u8, item, "back") or std.mem.eql(u8, item, "pressBack")) return .press_back;
    if (std.mem.eql(u8, item, "takeScreenshot")) return .snapshot;
    if (std.mem.eql(u8, item, "eraseText")) return .{ .erase_text = 80 };
    if (std.mem.eql(u8, item, "waitForAnimationToEnd")) return .{ .sleep_ms = 1000 };
    return error.UnsupportedImportCommand;
}

fn parseFlowYamlCommandWithValue(
    allocator: std.mem.Allocator,
    key: []const u8,
    value: []const u8,
    block: []const []const u8,
) !ImportedStep {
    if (std.mem.eql(u8, key, "tapOn")) {
        return .{ .tap = try parseSelectorValueOrBlock(allocator, value, block) };
    }
    if (std.mem.eql(u8, key, "inputText")) {
        return .{ .type_text = try parseRequiredScalarOrBlockValue(allocator, value, block, "text") };
    }
    if (std.mem.eql(u8, key, "eraseText")) {
        const parsed = if (value.len == 0) try parseOptionalU32FromBlock(block, "characters") else try parseU32(value);
        return .{ .erase_text = parsed orelse 80 };
    }
    if (std.mem.eql(u8, key, "hideKeyboard")) return .hide_keyboard;
    if (std.mem.eql(u8, key, "back") or std.mem.eql(u8, key, "pressBack")) return .press_back;
    if (std.mem.eql(u8, key, "launchApp")) return .launch;
    if (std.mem.eql(u8, key, "stopApp")) return .stop;
    if (std.mem.eql(u8, key, "clearState") or std.mem.eql(u8, key, "clearAppState")) return .clear_state;
    if (std.mem.eql(u8, key, "takeScreenshot")) return .snapshot;
    if (std.mem.eql(u8, key, "openLink")) {
        return .{ .open_link = try parseRequiredScalarOrBlockValue(allocator, value, block, "link") };
    }
    if (std.mem.eql(u8, key, "assertVisible")) {
        return .{ .assert_visible = try parseSelectorValueOrBlock(allocator, value, block) };
    }
    if (std.mem.eql(u8, key, "assertNotVisible")) {
        return .{ .assert_not_visible = try parseSelectorValueOrBlock(allocator, value, block) };
    }
    if (std.mem.eql(u8, key, "waitUntilVisible")) {
        return .{ .wait_visible = .{
            .selector = try parseSelectorValueOrBlock(allocator, value, block),
            .timeout_ms = (try parseOptionalU64FromBlock(block, "timeout")) orelse 5000,
        } };
    }
    if (std.mem.eql(u8, key, "waitUntilNotVisible")) {
        return .{ .wait_not_visible = .{
            .selector = try parseSelectorValueOrBlock(allocator, value, block),
            .timeout_ms = (try parseOptionalU64FromBlock(block, "timeout")) orelse 5000,
        } };
    }
    if (std.mem.eql(u8, key, "scrollUntilVisible")) {
        var scroll = ScrollStep{
            .selector = try parseSelectorValueOrBlock(allocator, value, block),
            .direction = (try parseDirectionFromBlock(block)) orelse "down",
            .timeout_ms = (try parseOptionalU64FromBlock(block, "timeout")) orelse 5000,
        };
        errdefer scroll.deinit(allocator);
        if (try parseOptionalU64FromBlock(block, "timeoutMs")) |timeout| scroll.timeout_ms = timeout;
        return .{ .scroll_until_visible = scroll };
    }
    if (std.mem.eql(u8, key, "waitForAnimationToEnd")) {
        return .{ .sleep_ms = if (value.len == 0) ((try parseOptionalU64FromBlock(block, "timeout")) orelse 1000) else try parseU64(value) };
    }
    return error.UnsupportedImportCommand;
}

fn parseSelectorValueOrBlock(allocator: std.mem.Allocator, value: []const u8, block: []const []const u8) !SelectorSpec {
    if (value.len > 0) return .{ .text = try parseScalarString(allocator, value) };
    const parsed = try parseSelectorBlock(allocator, block);
    if (!parsed.hasAny()) return error.ImportMissingSelector;
    return parsed;
}

fn parseSelectorBlock(allocator: std.mem.Allocator, block: []const []const u8) !SelectorSpec {
    var out = SelectorSpec{};
    errdefer out.deinit(allocator);
    for (block) |line| {
        const trimmed = trim(line);
        if (trimmed.len == 0 or std.mem.startsWith(u8, trimmed, "#")) continue;
        const pair = splitColon(trimmed) orelse continue;
        if (std.mem.eql(u8, pair.key, "id")) {
            replaceString(allocator, &out.id, try parseScalarString(allocator, pair.value));
        } else if (std.mem.eql(u8, pair.key, "text")) {
            replaceString(allocator, &out.text, try parseScalarString(allocator, pair.value));
        } else if (std.mem.eql(u8, pair.key, "textContains") or std.mem.eql(u8, pair.key, "contains")) {
            replaceString(allocator, &out.text_contains, try parseScalarString(allocator, pair.value));
        } else if (std.mem.eql(u8, pair.key, "contentDescription") or std.mem.eql(u8, pair.key, "contentDesc")) {
            replaceString(allocator, &out.content_desc, try parseScalarString(allocator, pair.value));
        } else if (std.mem.eql(u8, pair.key, "element") and pair.value.len > 0) {
            if (!out.hasAny()) out.text = try parseScalarString(allocator, pair.value);
        }
    }
    return out;
}

fn parseRequiredScalarOrBlockValue(allocator: std.mem.Allocator, value: []const u8, block: []const []const u8, block_key: []const u8) ![]const u8 {
    if (value.len > 0) return try parseScalarString(allocator, value);
    for (block) |line| {
        const pair = splitColon(trim(line)) orelse continue;
        if (std.mem.eql(u8, pair.key, block_key) or std.mem.eql(u8, pair.key, "value")) {
            return try parseScalarString(allocator, pair.value);
        }
    }
    return error.ImportMissingValue;
}

fn parseDirectionFromBlock(block: []const []const u8) !?[]const u8 {
    for (block) |line| {
        const pair = splitColon(trim(line)) orelse continue;
        if (!std.mem.eql(u8, pair.key, "direction")) continue;
        const value = normalizeScalar(pair.value);
        if (equalsIgnoreCase(value, "DOWN")) return "down";
        if (equalsIgnoreCase(value, "UP")) return "up";
        return error.UnsupportedImportDirection;
    }
    return null;
}

fn parseOptionalU64FromBlock(block: []const []const u8, key: []const u8) !?u64 {
    for (block) |line| {
        const pair = splitColon(trim(line)) orelse continue;
        if (std.mem.eql(u8, pair.key, key)) return try parseU64(pair.value);
    }
    return null;
}

fn parseOptionalU32FromBlock(block: []const []const u8, key: []const u8) !?u32 {
    const value = (try parseOptionalU64FromBlock(block, key)) orelse return null;
    if (value > std.math.maxInt(u32)) return error.ImportNumberOutOfRange;
    return @intCast(value);
}

fn replaceString(allocator: std.mem.Allocator, target: *?[]const u8, value: []const u8) void {
    if (target.*) |old| allocator.free(old);
    target.* = value;
}

const Pair = struct {
    key: []const u8,
    value: []const u8,
};

fn splitColon(line: []const u8) ?Pair {
    const index = std.mem.indexOfScalar(u8, line, ':') orelse return null;
    return .{
        .key = trim(line[0..index]),
        .value = trim(line[index + 1 ..]),
    };
}

fn parseScalarString(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    const normalized = normalizeScalar(value);
    if (normalized.len >= 2 and normalized[0] == '"' and normalized[normalized.len - 1] == '"') {
        return try unescapeDoubleQuoted(allocator, normalized[1 .. normalized.len - 1]);
    }
    if (normalized.len >= 2 and normalized[0] == '\'' and normalized[normalized.len - 1] == '\'') {
        return try allocator.dupe(u8, normalized[1 .. normalized.len - 1]);
    }
    return try allocator.dupe(u8, normalized);
}

fn normalizeScalar(value: []const u8) []const u8 {
    return trim(value);
}

fn unescapeDoubleQuoted(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    var index: usize = 0;
    while (index < value.len) : (index += 1) {
        if (value[index] != '\\' or index + 1 >= value.len) {
            try out.append(allocator, value[index]);
            continue;
        }
        index += 1;
        switch (value[index]) {
            '"' => try out.append(allocator, '"'),
            '\\' => try out.append(allocator, '\\'),
            'n' => try out.append(allocator, '\n'),
            'r' => try out.append(allocator, '\r'),
            't' => try out.append(allocator, '\t'),
            else => try out.append(allocator, value[index]),
        }
    }
    return try out.toOwnedSlice(allocator);
}

fn parseU64(value: []const u8) !u64 {
    return try std.fmt.parseInt(u64, normalizeScalar(value), 10);
}

fn parseU32(value: []const u8) !?u32 {
    const parsed = try parseU64(value);
    if (parsed > std.math.maxInt(u32)) return error.ImportNumberOutOfRange;
    return @intCast(parsed);
}

fn trim(value: []const u8) []const u8 {
    return std.mem.trim(u8, value, " \t\r\n");
}

fn equalsIgnoreCase(left: []const u8, right: []const u8) bool {
    return std.ascii.eqlIgnoreCase(left, right);
}

fn dupeOptional(allocator: std.mem.Allocator, value: ?[]const u8) !?[]const u8 {
    if (value) |actual| return try allocator.dupe(u8, actual);
    return null;
}

fn writeScenarioJson(writer: anytype, imported: ImportedScenario) !void {
    try writer.writeAll("{\n  \"name\": ");
    try trace.writeJsonString(writer, imported.name);
    if (imported.app_id) |app_id| {
        try writer.writeAll(",\n  \"appId\": ");
        try trace.writeJsonString(writer, app_id);
    }
    try writer.writeAll(",\n  \"steps\": [\n");
    for (imported.steps, 0..) |step, index| {
        if (index > 0) try writer.writeAll(",\n");
        try writer.writeAll("    ");
        try writeStepJson(writer, step);
    }
    try writer.writeAll("\n  ]\n}\n");
}

fn writeStepJson(writer: anytype, step: ImportedStep) !void {
    switch (step) {
        .launch => try writer.writeAll("{\"action\":\"launch\"}"),
        .stop => try writer.writeAll("{\"action\":\"stop\"}"),
        .clear_state => try writer.writeAll("{\"action\":\"clearState\"}"),
        .snapshot => try writer.writeAll("{\"action\":\"snapshot\"}"),
        .hide_keyboard => try writer.writeAll("{\"action\":\"hideKeyboard\"}"),
        .press_back => try writer.writeAll("{\"action\":\"pressBack\"}"),
        .open_link => |value| {
            try writer.writeAll("{\"action\":\"openLink\",\"url\":");
            try trace.writeJsonString(writer, value);
            try writer.writeAll("}");
        },
        .tap => |wanted| {
            try writer.writeAll("{\"action\":\"tap\",\"selector\":");
            try writeSelectorJson(writer, wanted);
            try writer.writeAll("}");
        },
        .type_text => |value| {
            try writer.writeAll("{\"action\":\"typeText\",\"text\":");
            try trace.writeJsonString(writer, value);
            try writer.writeAll("}");
        },
        .erase_text => |value| try writer.print("{{\"action\":\"eraseText\",\"maxChars\":{d}}}", .{value}),
        .assert_visible => |wanted| {
            try writer.writeAll("{\"action\":\"assertVisible\",\"selector\":");
            try writeSelectorJson(writer, wanted);
            try writer.writeAll("}");
        },
        .assert_not_visible => |wanted| {
            try writer.writeAll("{\"action\":\"assertNotVisible\",\"selector\":");
            try writeSelectorJson(writer, wanted);
            try writer.writeAll("}");
        },
        .wait_visible => |wait| {
            try writer.writeAll("{\"action\":\"waitVisible\",\"selector\":");
            try writeSelectorJson(writer, wait.selector);
            try writer.print(",\"timeoutMs\":{d}}}", .{wait.timeout_ms});
        },
        .wait_not_visible => |wait| {
            try writer.writeAll("{\"action\":\"waitNotVisible\",\"selector\":");
            try writeSelectorJson(writer, wait.selector);
            try writer.print(",\"timeoutMs\":{d}}}", .{wait.timeout_ms});
        },
        .scroll_until_visible => |scroll| {
            try writer.writeAll("{\"action\":\"scrollUntilVisible\",\"selector\":");
            try writeSelectorJson(writer, scroll.selector);
            try writer.writeAll(",\"direction\":");
            try trace.writeJsonString(writer, scroll.direction);
            try writer.print(",\"timeoutMs\":{d}}}", .{scroll.timeout_ms});
        },
        .sleep_ms => |value| try writer.print("{{\"action\":\"sleep\",\"ms\":{d}}}", .{value}),
    }
}

fn writeSelectorJson(writer: anytype, wanted: SelectorSpec) !void {
    try writer.writeAll("{");
    var first = true;
    if (wanted.id) |value| {
        try writeSelectorField(writer, "id", value, &first);
    }
    if (wanted.text) |value| {
        try writeSelectorField(writer, "text", value, &first);
    }
    if (wanted.text_contains) |value| {
        try writeSelectorField(writer, "textContains", value, &first);
    }
    if (wanted.content_desc) |value| {
        try writeSelectorField(writer, "contentDesc", value, &first);
    }
    try writer.writeAll("}");
}

fn writeSelectorField(writer: anytype, key: []const u8, value: []const u8, first: *bool) !void {
    if (!first.*) try writer.writeAll(",");
    first.* = false;
    try writer.writeAll("\"");
    try writer.writeAll(key);
    try writer.writeAll("\":");
    try trace.writeJsonString(writer, value);
}

test "flow-yaml importer translates common commands to zmr scenario json" {
    const allocator = std.testing.allocator;
    var imported = try parseFlowYamlSlice(allocator,
        \\appId: com.example.imported
        \\name: Imported smoke
        \\---
        \\- launchApp
        \\- tapOn: "Sign in"
        \\- inputText: "agent@example.com"
        \\- assertVisible:
        \\    id: dashboard-title
        \\- scrollUntilVisible:
        \\    element:
        \\      text: "Invite a teammate"
        \\    direction: DOWN
        \\    timeout: 7000
        \\
    , .{});
    defer imported.deinit(allocator);

    try std.testing.expectEqualStrings("Imported smoke", imported.name);
    try std.testing.expectEqualStrings("com.example.imported", imported.app_id.?);
    try std.testing.expectEqual(@as(usize, 5), imported.steps.len);

    var buffer = std.ArrayList(u8).empty;
    defer buffer.deinit(allocator);
    try writeScenarioJson(buffer.writer(allocator), imported);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"action\":\"scrollUntilVisible\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"direction\":\"down\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, buffer.items, "\"timeoutMs\":7000") != null);
}
