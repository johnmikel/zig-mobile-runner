const trace = @import("trace.zig");
const model = @import("importer_model.zig");

pub fn writeScenarioJson(writer: anytype, imported: model.ImportedScenario) !void {
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

fn writeStepJson(writer: anytype, step: model.ImportedStep) !void {
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

fn writeSelectorJson(writer: anytype, wanted: model.SelectorSpec) !void {
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
