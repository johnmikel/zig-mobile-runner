const std = @import("std");
const scenario = @import("scenario.zig");
const selector = @import("selector.zig");
const trace = @import("trace.zig");
const types = @import("types.zig");

pub const RunOptions = struct {
    settle_ms: u64 = 500,
    poll_ms: u64 = 500,
    default_timeout_ms: u64 = 5000,
    action_timeout_ms: u64 = 5000,
};

pub fn runScenario(
    allocator: std.mem.Allocator,
    device: anytype,
    script: scenario.Scenario,
    writer: ?*trace.TraceWriter,
    options: RunOptions,
) !void {
    if (writer) |tw| {
        try tw.startManifest(script.name, script.app_id);
        const payload = try eventString(tw.allocator, script.name);
        defer tw.allocator.free(payload);
        try tw.recordEvent("scenario.start", payload);
    }
    for (script.steps, 0..) |step, index| {
        executeStep(allocator, device, step, writer, options) catch |err| {
            if (writer) |tw| {
                try recordStepError(tw, index, err);
                try recordScenarioEnd(tw, script.name, "failed", index, err);
                try tw.finishManifest(.{
                    .status = "failed",
                    .failed_step_index = index,
                    .error_name = @errorName(err),
                });
            }
            return err;
        };
        if (writer) |tw| {
            const payload = try std.fmt.allocPrint(tw.allocator, "{{\"index\":{d}}}", .{index});
            defer tw.allocator.free(payload);
            try tw.recordEvent("step.done", payload);
        }
    }
    if (writer) |tw| {
        try recordScenarioEnd(tw, script.name, "passed", null, null);
        try tw.finishManifest(.{ .status = "passed" });
    }
}

pub fn executeStep(
    allocator: std.mem.Allocator,
    device: anytype,
    step: scenario.Step,
    writer: ?*trace.TraceWriter,
    options: RunOptions,
) !void {
    switch (step) {
        .launch => {
            try device.launch();
            try settleDevice(device, options);
        },
        .stop => try device.stop(),
        .clear_state => try device.clearState(),
        .snapshot => {
            var snap = try device.snapshot(writer);
            defer snap.deinit(device.allocator);
            if (writer) |tw| {
                const path = try tw.writeSnapshot(snap);
                defer tw.allocator.free(path);
                const payload = try eventString(tw.allocator, path);
                defer tw.allocator.free(payload);
                try tw.recordEvent("observe.snapshot", payload);
            }
        },
        .open_link => |url| {
            try device.openLink(url);
            try settleDevice(device, options);
        },
        .tap => |wanted| try tapSelector(device, wanted, writer, options),
        .type_text => |input| {
            if (input.selector) |wanted| try tapSelector(device, wanted, writer, options);
            try device.typeText(input.text);
            try settleDevice(device, options);
        },
        .erase_text => |input| {
            if (input.selector) |wanted| try tapSelector(device, wanted, writer, options);
            try device.eraseText(input.max_chars);
            if (writer) |tw| {
                const payload = try std.fmt.allocPrint(tw.allocator, "{{\"maxChars\":{d}}}", .{input.max_chars});
                defer tw.allocator.free(payload);
                try tw.recordEvent("ui.eraseText", payload);
            }
            try settleDevice(device, options);
        },
        .press_back => {
            try device.pressBack();
            try settleDevice(device, options);
        },
        .hide_keyboard => {
            try device.hideKeyboard();
            if (writer) |tw| try tw.recordEvent("ui.hideKeyboard", "{\"status\":\"ok\"}");
            try settleDevice(device, options);
        },
        .swipe => |swipe| {
            try device.swipe(swipe.x1, swipe.y1, swipe.x2, swipe.y2, swipe.duration_ms);
            try settleDevice(device, options);
        },
        .wait_visible => |wait| {
            if (!try waitUntilVisible(device, wait.selector, wait.timeout_ms, writer, options)) return error.WaitTimeout;
        },
        .wait_not_visible => |wait| {
            if (!try waitUntilNotVisible(device, wait.selector, wait.timeout_ms, writer, options)) return error.WaitTimeout;
        },
        .wait_any => |wait| {
            if (try waitUntilAnyVisible(device, wait.selectors, wait.timeout_ms, writer, options) == null) return error.WaitTimeout;
        },
        .assert_visible => |wanted| {
            if (!try waitUntilVisible(device, wanted, options.default_timeout_ms, writer, options)) return error.AssertionFailed;
        },
        .assert_not_visible => |wanted| {
            if (!try waitUntilNotVisible(device, wanted, options.default_timeout_ms, writer, options)) return error.AssertionFailed;
        },
        .optional => |inner| {
            executeStep(allocator, device, inner.*, writer, options) catch |err| {
                if (writer) |tw| {
                    const payload = try std.fmt.allocPrint(tw.allocator, "{{\"status\":\"skipped\",\"error\":\"{s}\"}}", .{@errorName(err)});
                    defer tw.allocator.free(payload);
                    try tw.recordEvent("step.optional", payload);
                }
            };
        },
        .when_visible => |block| {
            const visible = if (block.timeout_ms == 0)
                try isVisibleNow(device, block.selector, writer)
            else
                try waitUntilVisible(device, block.selector, block.timeout_ms, writer, options);
            if (visible) {
                for (block.steps) |inner| try executeStep(allocator, device, inner, writer, options);
            } else if (writer) |tw| {
                try recordSelectorEvent(tw, "step.whenVisible.skipped", block.selector);
            }
        },
        .repeat => |block| {
            var iteration: u32 = 0;
            while (iteration < block.times) : (iteration += 1) {
                if (writer) |tw| {
                    const payload = try std.fmt.allocPrint(tw.allocator, "{{\"iteration\":{d},\"times\":{d}}}", .{ iteration + 1, block.times });
                    defer tw.allocator.free(payload);
                    try tw.recordEvent("step.repeat.iteration", payload);
                }
                for (block.steps) |inner| try executeStep(allocator, device, inner, writer, options);
            }
        },
        .scroll_until_visible => |scroll| {
            if (!try scrollUntilVisible(device, scroll.selector, scroll.timeout_ms, scroll.direction, writer, options)) return error.WaitTimeout;
        },
        .sleep_ms => |ms| try sleepMs(ms),
    }
}

pub fn tapSelector(
    device: anytype,
    wanted: selector.Selector,
    writer: ?*trace.TraceWriter,
    options: RunOptions,
) !void {
    const deadline = std.time.milliTimestamp() + @as(i64, @intCast(options.action_timeout_ms));
    var attempts: u32 = 0;
    while (true) {
        attempts += 1;
        var snap = try device.snapshot(writer);
        defer snap.deinit(device.allocator);
        if (findActionable(snap, wanted)) |node| {
            try device.tap(node.bounds.centerX(), node.bounds.centerY());
            if (writer) |tw| {
                var payload = std.ArrayList(u8).empty;
                defer payload.deinit(tw.allocator);
                try payload.writer(tw.allocator).print("{{\"snapshotId\":\"{s}\",\"target\":\"{s}\",\"x\":{d},\"y\":{d},\"attempts\":{d},\"selector\":", .{
                    snap.id,
                    node.stable_id,
                    node.bounds.centerX(),
                    node.bounds.centerY(),
                    attempts,
                });
                try trace.writeSelectorJson(payload.writer(tw.allocator), wanted);
                try payload.writer(tw.allocator).writeAll("}");
                try tw.recordEvent("ui.tap", payload.items);
            }
            try settleDevice(device, options);
            return;
        }
        if (std.time.milliTimestamp() >= deadline) {
            if (writer) |tw| {
                try recordSelectorMiss(tw, "ui.tap.notFound", wanted, snap);
            }
            return error.SelectorNotFound;
        }
        try sleepMs(options.poll_ms);
    }
}

fn findActionable(snap: types.ObservationSnapshot, wanted: selector.Selector) ?types.UiNode {
    for (snap.nodes) |node| {
        if (!selector.matches(node, wanted)) continue;
        if (!node.enabled) continue;
        if (!isInViewport(node, snap.viewport)) continue;
        return node;
    }
    return null;
}

pub fn waitUntilVisible(
    device: anytype,
    wanted: selector.Selector,
    timeout_ms: u64,
    writer: ?*trace.TraceWriter,
    options: RunOptions,
) !bool {
    const deadline = std.time.milliTimestamp() + @as(i64, @intCast(timeout_ms));
    while (true) {
        var snap = try device.snapshot(writer);
        defer snap.deinit(device.allocator);
        if (selector.find(snap.nodes, wanted) != null) {
            if (writer) |tw| try tw.recordEvent("wait.visible", "{\"status\":\"ok\"}");
            return true;
        }
        if (std.time.milliTimestamp() >= deadline) {
            if (writer) |tw| {
                const selectors = [_]selector.Selector{wanted};
                try recordWaitTimeout(tw, "wait.visible", selectors[0..], snap);
            }
            return false;
        }
        try sleepMs(options.poll_ms);
    }
}

pub fn waitUntilNotVisible(
    device: anytype,
    wanted: selector.Selector,
    timeout_ms: u64,
    writer: ?*trace.TraceWriter,
    options: RunOptions,
) !bool {
    const deadline = std.time.milliTimestamp() + @as(i64, @intCast(timeout_ms));
    while (true) {
        var snap = try device.snapshot(writer);
        defer snap.deinit(device.allocator);
        if (selector.find(snap.nodes, wanted) == null) {
            if (writer) |tw| try tw.recordEvent("wait.notVisible", "{\"status\":\"ok\"}");
            return true;
        }
        if (std.time.milliTimestamp() >= deadline) {
            if (writer) |tw| {
                const selectors = [_]selector.Selector{wanted};
                try recordWaitTimeout(tw, "wait.notVisible", selectors[0..], snap);
            }
            return false;
        }
        try sleepMs(options.poll_ms);
    }
}

pub fn waitUntilAnyVisible(
    device: anytype,
    selectors: []const selector.Selector,
    timeout_ms: u64,
    writer: ?*trace.TraceWriter,
    options: RunOptions,
) !?usize {
    const deadline = std.time.milliTimestamp() + @as(i64, @intCast(timeout_ms));
    while (true) {
        var snap = try device.snapshot(writer);
        defer snap.deinit(device.allocator);
        for (selectors, 0..) |wanted, index| {
            if (selector.find(snap.nodes, wanted)) |node| {
                if (writer) |tw| {
                    var payload = std.ArrayList(u8).empty;
                    defer payload.deinit(tw.allocator);
                    try payload.writer(tw.allocator).print("{{\"status\":\"ok\",\"matchedIndex\":{d},\"target\":\"{s}\",\"selector\":", .{ index, node.stable_id });
                    try trace.writeSelectorJson(payload.writer(tw.allocator), wanted);
                    try payload.writer(tw.allocator).writeAll("}");
                    try tw.recordEvent("wait.any", payload.items);
                }
                return index;
            }
        }
        if (std.time.milliTimestamp() >= deadline) {
            if (writer) |tw| try recordWaitTimeout(tw, "wait.any", selectors, snap);
            return null;
        }
        try sleepMs(options.poll_ms);
    }
}

pub fn scrollUntilVisible(
    device: anytype,
    wanted: selector.Selector,
    timeout_ms: u64,
    direction: scenario.ScrollDirection,
    writer: ?*trace.TraceWriter,
    options: RunOptions,
) !bool {
    const deadline = std.time.milliTimestamp() + @as(i64, @intCast(timeout_ms));
    while (true) {
        var snap = try device.snapshot(writer);
        defer snap.deinit(device.allocator);
        if (selector.find(snap.nodes, wanted)) |node| {
            if (writer) |tw| {
                var payload = std.ArrayList(u8).empty;
                defer payload.deinit(tw.allocator);
                try payload.writer(tw.allocator).print("{{\"status\":\"ok\",\"target\":\"{s}\",\"selector\":", .{node.stable_id});
                try trace.writeSelectorJson(payload.writer(tw.allocator), wanted);
                try payload.writer(tw.allocator).writeAll("}");
                try tw.recordEvent("ui.scrollUntilVisible", payload.items);
            }
            return true;
        }
        if (std.time.milliTimestamp() >= deadline) {
            if (writer) |tw| {
                const selectors = [_]selector.Selector{wanted};
                try recordWaitTimeout(tw, "ui.scrollUntilVisible", selectors[0..], snap);
            }
            return false;
        }

        const width = if (snap.viewport.width == 0) @as(i32, 720) else @as(i32, @intCast(snap.viewport.width));
        const height = if (snap.viewport.height == 0) @as(i32, 1280) else @as(i32, @intCast(snap.viewport.height));
        const x = @divTrunc(width, 2);
        const start_y = switch (direction) {
            .down => @divTrunc(height * 4, 5),
            .up => @divTrunc(height * 3, 10),
        };
        const end_y = switch (direction) {
            .down => @divTrunc(height * 3, 10),
            .up => @divTrunc(height * 4, 5),
        };
        try device.swipe(x, start_y, x, end_y, 350);
        if (writer) |tw| {
            const payload = try std.fmt.allocPrint(tw.allocator, "{{\"direction\":\"{s}\",\"x\":{d},\"y1\":{d},\"y2\":{d}}}", .{
                if (direction == .down) "down" else "up",
                x,
                start_y,
                end_y,
            });
            defer tw.allocator.free(payload);
            try tw.recordEvent("ui.scroll", payload);
        }
        try settleDevice(device, options);
    }
}

fn isVisibleNow(
    device: anytype,
    wanted: selector.Selector,
    writer: ?*trace.TraceWriter,
) !bool {
    var snap = try device.snapshot(writer);
    defer snap.deinit(device.allocator);
    return selector.find(snap.nodes, wanted) != null;
}

fn sleepMs(ms: u64) !void {
    std.Thread.sleep(ms * std.time.ns_per_ms);
}

fn settleDevice(device: anytype, options: RunOptions) !void {
    try device.settle(options.settle_ms);
}

fn eventString(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    var buffer = std.ArrayList(u8).empty;
    errdefer buffer.deinit(allocator);
    try buffer.writer(allocator).writeAll("{\"value\":");
    try trace.writeJsonString(buffer.writer(allocator), value);
    try buffer.writer(allocator).writeAll("}");
    return try buffer.toOwnedSlice(allocator);
}

fn recordSelectorEvent(tw: *trace.TraceWriter, kind: []const u8, wanted: selector.Selector) !void {
    var payload = std.ArrayList(u8).empty;
    defer payload.deinit(tw.allocator);
    try payload.writer(tw.allocator).writeAll("{\"selector\":");
    try trace.writeSelectorJson(payload.writer(tw.allocator), wanted);
    try payload.writer(tw.allocator).writeAll("}");
    try tw.recordEvent(kind, payload.items);
}

fn recordStepError(tw: *trace.TraceWriter, index: usize, err: anyerror) !void {
    const payload = try std.fmt.allocPrint(
        tw.allocator,
        "{{\"index\":{d},\"error\":\"{s}\"}}",
        .{ index, @errorName(err) },
    );
    defer tw.allocator.free(payload);
    try tw.recordEvent("step.error", payload);
}

fn recordScenarioEnd(
    tw: *trace.TraceWriter,
    name: []const u8,
    status: []const u8,
    failed_index: ?usize,
    err: ?anyerror,
) !void {
    var payload = std.ArrayList(u8).empty;
    defer payload.deinit(tw.allocator);
    const writer = payload.writer(tw.allocator);
    try writer.writeAll("{\"value\":");
    try trace.writeJsonString(writer, name);
    try writer.writeAll(",\"status\":");
    try trace.writeJsonString(writer, status);
    if (failed_index) |index| {
        try writer.print(",\"failedStepIndex\":{d}", .{index});
    }
    if (err) |actual| {
        try writer.writeAll(",\"error\":");
        try trace.writeJsonString(writer, @errorName(actual));
    }
    try writer.writeAll("}");
    try tw.recordEvent("scenario.end", payload.items);
}

fn recordSelectorMiss(
    tw: *trace.TraceWriter,
    kind: []const u8,
    wanted: selector.Selector,
    snap: types.ObservationSnapshot,
) !void {
    const selectors = [_]selector.Selector{wanted};
    try recordDiagnostic(tw, kind, "not_found", selectors[0..], snap);
}

fn recordWaitTimeout(
    tw: *trace.TraceWriter,
    kind: []const u8,
    selectors: []const selector.Selector,
    snap: types.ObservationSnapshot,
) !void {
    try recordDiagnostic(tw, kind, "timeout", selectors, snap);
}

fn recordDiagnostic(
    tw: *trace.TraceWriter,
    kind: []const u8,
    status: []const u8,
    selectors: []const selector.Selector,
    snap: types.ObservationSnapshot,
) !void {
    var payload = std.ArrayList(u8).empty;
    defer payload.deinit(tw.allocator);
    const writer = payload.writer(tw.allocator);
    try writer.print("{{\"status\":\"{s}\",\"snapshotId\":\"{s}\",\"selectors\":[", .{ status, snap.id });
    for (selectors, 0..) |wanted, index| {
        if (index > 0) try writer.writeAll(",");
        try trace.writeSelectorJson(writer, wanted);
    }
    try writer.writeAll("],\"activePackage\":");
    if (snap.active_package) |value| {
        try trace.writeJsonString(writer, value);
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"activeActivity\":");
    if (snap.active_activity) |value| {
        try trace.writeJsonString(writer, value);
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"visibleTexts\":[");
    var count: usize = 0;
    for (snap.nodes) |node| {
        const text = node.text orelse node.content_desc orelse continue;
        if (!node.visible or text.len == 0) continue;
        if (count > 0) try writer.writeAll(",");
        try trace.writeJsonString(writer, text);
        count += 1;
        if (count >= 20) break;
    }
    try writer.writeAll("]");
    try writeCandidateList(writer, "hiddenCandidates", selectors, snap, .hidden);
    try writeCandidateList(writer, "disabledCandidates", selectors, snap, .disabled);
    try writeCandidateList(writer, "offscreenCandidates", selectors, snap, .offscreen);
    try writeNearestTextMatches(writer, selectors, snap);
    try writer.writeAll("}");
    try tw.recordEvent(kind, payload.items);
}

const CandidateKind = enum {
    hidden,
    disabled,
    offscreen,
};

fn writeCandidateList(
    writer: anytype,
    field_name: []const u8,
    selectors: []const selector.Selector,
    snap: types.ObservationSnapshot,
    candidate_kind: CandidateKind,
) !void {
    try writer.print(",\"{s}\":[", .{field_name});
    var count: usize = 0;
    for (snap.nodes) |node| {
        var matched = false;
        for (selectors) |wanted| {
            if (nodeMatchesSelectorFields(node, wanted)) {
                matched = true;
                break;
            }
        }
        if (!matched) continue;
        const include = switch (candidate_kind) {
            .hidden => !node.visible,
            .disabled => node.visible and !node.enabled,
            .offscreen => node.visible and node.enabled and !isInViewport(node, snap.viewport),
        };
        if (!include) continue;
        if (count > 0) try writer.writeAll(",");
        try writeNodeDiagnostic(writer, node);
        count += 1;
        if (count >= 10) break;
    }
    try writer.writeAll("]");
}

fn writeNearestTextMatches(writer: anytype, selectors: []const selector.Selector, snap: types.ObservationSnapshot) !void {
    try writer.writeAll(",\"nearestTextMatches\":[");
    var written: usize = 0;
    for (selectors) |wanted| {
        const target = selectorTextTarget(wanted) orelse continue;
        var best: [5]NearestCandidate = undefined;
        var best_len: usize = 0;
        for (snap.nodes) |node| {
            const label = nodeLabel(node) orelse continue;
            if (label.len == 0 or nodeMatchesSelectorFields(node, wanted)) continue;
            const score = textDistance(target, label);
            if (score > @max(target.len, label.len)) continue;
            insertNearest(&best, &best_len, .{ .node = node, .text = label, .score = score });
        }
        for (best[0..best_len]) |candidate| {
            if (written > 0) try writer.writeAll(",");
            try writer.writeAll("{\"stableId\":");
            try trace.writeJsonString(writer, candidate.node.stable_id);
            try writer.writeAll(",\"text\":");
            try trace.writeJsonString(writer, candidate.text);
            try writer.print(",\"score\":{d}", .{candidate.score});
            try writer.writeAll(",\"enabled\":");
            try writer.writeAll(if (candidate.node.enabled) "true" else "false");
            try writer.writeAll(",\"visible\":");
            try writer.writeAll(if (candidate.node.visible) "true" else "false");
            try writer.writeAll("}");
            written += 1;
            if (written >= 10) break;
        }
        if (written >= 10) break;
    }
    try writer.writeAll("]");
}

const NearestCandidate = struct {
    node: types.UiNode,
    text: []const u8,
    score: usize,
};

fn insertNearest(candidates: *[5]NearestCandidate, len: *usize, candidate: NearestCandidate) void {
    const insert_limit = candidates.len;
    if (len.* == insert_limit and candidate.score >= candidates[len.* - 1].score) return;
    var index: usize = 0;
    while (index < len.* and candidates[index].score <= candidate.score) : (index += 1) {}
    if (len.* < insert_limit) len.* += 1;
    var move_index = len.* - 1;
    while (move_index > index) : (move_index -= 1) {
        candidates[move_index] = candidates[move_index - 1];
    }
    candidates[index] = candidate;
}

fn writeNodeDiagnostic(writer: anytype, node: types.UiNode) !void {
    try writer.writeAll("{\"stableId\":");
    try trace.writeJsonString(writer, node.stable_id);
    try writer.writeAll(",\"className\":");
    try trace.writeJsonString(writer, node.class_name);
    try writer.writeAll(",\"text\":");
    if (node.text) |value| {
        try trace.writeJsonString(writer, value);
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"contentDesc\":");
    if (node.content_desc) |value| {
        try trace.writeJsonString(writer, value);
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll(",\"resourceId\":");
    if (node.resource_id) |value| {
        try trace.writeJsonString(writer, value);
    } else {
        try writer.writeAll("null");
    }
    try writer.print(
        ",\"bounds\":{{\"x\":{d},\"y\":{d},\"width\":{d},\"height\":{d}}}",
        .{ node.bounds.x, node.bounds.y, node.bounds.width, node.bounds.height },
    );
    try writer.writeAll(",\"enabled\":");
    try writer.writeAll(if (node.enabled) "true" else "false");
    try writer.writeAll(",\"visible\":");
    try writer.writeAll(if (node.visible) "true" else "false");
    try writer.writeAll("}");
}

fn nodeMatchesSelectorFields(node: types.UiNode, wanted: selector.Selector) bool {
    if (wanted.id) |id| {
        if (node.resource_id == null or !std.mem.eql(u8, node.resource_id.?, id)) return false;
    }
    if (wanted.text) |text| {
        if (node.text == null or !std.mem.eql(u8, node.text.?, text)) return false;
    }
    if (wanted.text_contains) |needle| {
        if (node.text == null or std.mem.indexOf(u8, node.text.?, needle) == null) return false;
    }
    if (wanted.content_desc) |desc| {
        if (node.content_desc == null or !std.mem.eql(u8, node.content_desc.?, desc)) return false;
    }
    if (wanted.content_desc_contains) |needle| {
        if (node.content_desc == null or std.mem.indexOf(u8, node.content_desc.?, needle) == null) return false;
    }
    if (wanted.class_name) |class_name| {
        if (!std.mem.eql(u8, node.class_name, class_name)) return false;
    }
    return true;
}

fn selectorTextTarget(wanted: selector.Selector) ?[]const u8 {
    if (wanted.text) |value| return value;
    if (wanted.text_contains) |value| return value;
    if (wanted.content_desc) |value| return value;
    if (wanted.content_desc_contains) |value| return value;
    return null;
}

fn nodeLabel(node: types.UiNode) ?[]const u8 {
    if (node.text) |value| return value;
    if (node.content_desc) |value| return value;
    return null;
}

fn isInViewport(node: types.UiNode, viewport: types.Viewport) bool {
    if (node.bounds.width <= 0 or node.bounds.height <= 0) return false;
    if (viewport.width == 0 or viewport.height == 0) return true;
    const right = node.bounds.x + node.bounds.width;
    const bottom = node.bounds.y + node.bounds.height;
    return right > 0 and bottom > 0 and node.bounds.x < @as(i32, @intCast(viewport.width)) and node.bounds.y < @as(i32, @intCast(viewport.height));
}

fn textDistance(left: []const u8, right: []const u8) usize {
    if (containsIgnoreCase(left, right) or containsIgnoreCase(right, left)) {
        return if (left.len > right.len) left.len - right.len else right.len - left.len;
    }
    const prefix = commonPrefixIgnoreCase(left, right);
    return @max(left.len, right.len) - prefix;
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    var index: usize = 0;
    while (index + needle.len <= haystack.len) : (index += 1) {
        var matched = true;
        for (needle, 0..) |needle_ch, offset| {
            if (std.ascii.toLower(haystack[index + offset]) != std.ascii.toLower(needle_ch)) {
                matched = false;
                break;
            }
        }
        if (matched) return true;
    }
    return false;
}

fn commonPrefixIgnoreCase(left: []const u8, right: []const u8) usize {
    const limit = @min(left.len, right.len);
    var index: usize = 0;
    while (index < limit) : (index += 1) {
        if (std.ascii.toLower(left[index]) != std.ascii.toLower(right[index])) break;
    }
    return index;
}

test "wait any matches the first visible selector candidate" {
    const fake_device = @import("fake_device.zig");
    const allocator = std.testing.allocator;
    const nodes = try allocator.alloc(types.UiNode, 1);
    nodes[0] = .{
        .stable_id = try allocator.dupe(u8, "node-home"),
        .class_name = try allocator.dupe(u8, "android.widget.TextView"),
        .text = try allocator.dupe(u8, "Home"),
    };
    var snaps = try allocator.alloc(types.ObservationSnapshot, 1);
    snaps[0] = .{
        .id = try allocator.dupe(u8, "snapshot-1"),
        .timestamp_ms = 1,
        .nodes = nodes,
    };
    defer {
        snaps[0].deinit(allocator);
        allocator.free(snaps);
    }

    var fake = fake_device.FakeDevice.init(allocator, snaps);
    defer fake.deinit();
    const selectors = [_]selector.Selector{ .{ .text = "Missing" }, .{ .text = "Home" } };
    const matched = try waitUntilAnyVisible(&fake, selectors[0..], 10, null, .{ .settle_ms = 0, .poll_ms = 1 });
    try std.testing.expectEqual(@as(?usize, 1), matched);
}

test "tap retries through transient empty snapshots" {
    const fake_device = @import("fake_device.zig");
    const allocator = std.testing.allocator;

    var snapshots = std.ArrayList(types.ObservationSnapshot).empty;
    defer {
        for (snapshots.items) |snap| snap.deinit(allocator);
        snapshots.deinit(allocator);
    }
    try appendTextSnapshot(allocator, &snapshots, "empty", null, .{});
    try appendTextSnapshot(allocator, &snapshots, "tap-target", "Tap Target", .{});

    var fake = fake_device.FakeDevice.init(allocator, snapshots.items);
    defer fake.deinit();

    try tapSelector(&fake, .{ .text = "Tap Target" }, null, .{ .settle_ms = 0, .poll_ms = 0, .action_timeout_ms = 100 });

    try std.testing.expectEqual(@as(usize, 1), fake.taps);
}

test "runner executes agent flow primitives and records trace events" {
    const fake_device = @import("fake_device.zig");
    const allocator = std.testing.allocator;
    const dir = "zig-cache-test-runner-flow";
    std.fs.cwd().deleteTree(dir) catch {};
    defer std.fs.cwd().deleteTree(dir) catch {};

    var snapshots = std.ArrayList(types.ObservationSnapshot).empty;
    defer {
        for (snapshots.items) |snap| snap.deinit(allocator);
        snapshots.deinit(allocator);
    }
    try appendTextSnapshot(allocator, &snapshots, "snap-start", "Start", .{});
    try appendTextSnapshot(allocator, &snapshots, "snap-tap", "Tap Target", .{});
    try appendTextSnapshot(allocator, &snapshots, "snap-type", "Email Field", .{});
    try appendTextSnapshot(allocator, &snapshots, "snap-erase", "Email Field", .{});
    try appendTextSnapshot(allocator, &snapshots, "snap-wait-visible", "Visible", .{});
    try appendTextSnapshot(allocator, &snapshots, "snap-wait-gone", "Different", .{});
    try appendTextSnapshot(allocator, &snapshots, "snap-wait-any", "Any Match", .{});
    try appendTextSnapshot(allocator, &snapshots, "snap-assert-visible", "Assert Me", .{});
    try appendTextSnapshot(allocator, &snapshots, "snap-assert-not-visible", "No Gone Here", .{});
    try appendTextSnapshot(allocator, &snapshots, "snap-optional-miss", "Alternative", .{});
    try appendTextSnapshot(allocator, &snapshots, "snap-conditional", "Conditional", .{});
    try appendTextSnapshot(allocator, &snapshots, "snap-skip-conditional", "Other Branch", .{});
    try appendTextSnapshot(allocator, &snapshots, "snap-scroll-before", "Before Scroll", .{ .width = 100, .height = 200 });
    try appendTextSnapshot(allocator, &snapshots, "snap-scroll-after", "Scroll Target", .{ .width = 100, .height = 200 });

    var fake = fake_device.FakeDevice.init(allocator, snapshots.items);
    defer fake.deinit();

    var tw = try trace.TraceWriter.init(allocator, dir);
    defer tw.deinit();

    const script_json =
        \\{
        \\  "name": "full flow",
        \\  "steps": [
        \\    {"action": "launch"},
        \\    {"action": "snapshot"},
        \\    {"action": "tap", "selector": {"text": "Tap Target"}},
        \\    {"action": "typeText", "selector": {"text": "Email Field"}, "text": "agent@example.com"},
        \\    {"action": "eraseText", "selector": {"text": "Email Field"}, "maxChars": 4},
        \\    {"action": "hideKeyboard"},
        \\    {"action": "swipe", "x1": 10, "y1": 20, "x2": 30, "y2": 40, "durationMs": 50},
        \\    {"action": "pressBack"},
        \\    {"action": "waitVisible", "selector": {"text": "Visible"}, "timeoutMs": 10},
        \\    {"action": "waitNotVisible", "selector": {"text": "Gone"}, "timeoutMs": 10},
        \\    {"action": "waitAny", "selectors": [{"text": "Missing"}, {"text": "Any Match"}], "timeoutMs": 10},
        \\    {"action": "assertVisible", "selector": {"text": "Assert Me"}},
        \\    {"action": "assertNotVisible", "selector": {"text": "Gone"}},
        \\    {"action": "optional", "step": {"action": "tap", "selector": {"text": "Missing Optional"}}},
        \\    {"action": "whenVisible", "selector": {"text": "Conditional"}, "steps": [
        \\      {"action": "typeText", "text": "conditional"}
        \\    ]},
        \\    {"action": "whenVisible", "selector": {"text": "Missing Branch"}, "steps": [
        \\      {"action": "typeText", "text": "not-run"}
        \\    ]},
        \\    {"action": "repeat", "times": 2, "steps": [
        \\      {"action": "eraseText", "maxChars": 1}
        \\    ]},
        \\    {"action": "scrollUntilVisible", "selector": {"text": "Scroll Target"}, "direction": "up", "timeoutMs": 1000},
        \\    {"action": "sleep", "ms": 0},
        \\    {"action": "stop"},
        \\    {"action": "clearState"}
        \\  ]
        \\}
    ;
    const script = try scenario.parseSlice(allocator, script_json);
    defer script.deinit(allocator);

    try runScenario(allocator, &fake, script, &tw, .{ .settle_ms = 0, .poll_ms = 0, .default_timeout_ms = 10, .action_timeout_ms = 0 });

    try std.testing.expect(fake.launched);
    try std.testing.expect(fake.stopped);
    try std.testing.expect(fake.cleared);
    try std.testing.expectEqual(@as(usize, 3), fake.taps);
    try std.testing.expectEqual(@as(usize, 2), fake.typed_text.items.len);
    try std.testing.expectEqualStrings("agent@example.com", fake.typed_text.items[0]);
    try std.testing.expectEqualStrings("conditional", fake.typed_text.items[1]);
    try std.testing.expectEqual(@as(usize, 3), fake.erases);
    try std.testing.expectEqual(@as(u32, 1), fake.last_erase_chars);
    try std.testing.expectEqual(@as(usize, 1), fake.hides_keyboard);
    try std.testing.expectEqual(@as(usize, 2), fake.swipes);
    try std.testing.expectEqual(@as(i32, 50), fake.last_swipe.?.x1);
    try std.testing.expectEqual(@as(i32, 60), fake.last_swipe.?.y1);
    try std.testing.expectEqual(@as(i32, 160), fake.last_swipe.?.y2);
    try std.testing.expectEqual(@as(usize, 1), fake.presses_back);

    const events_path = try std.fs.path.join(allocator, &.{ dir, "events.jsonl" });
    defer allocator.free(events_path);
    const events = try std.fs.cwd().readFileAlloc(allocator, events_path, 1024 * 1024);
    defer allocator.free(events);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"kind\":\"scenario.start\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"kind\":\"observe.snapshot\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"kind\":\"ui.tap\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"kind\":\"step.optional\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"kind\":\"step.whenVisible.skipped\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"kind\":\"ui.scrollUntilVisible\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"kind\":\"scenario.end\"") != null);
}

test "runner settles through the device hook after mutating actions" {
    const fake_device = @import("fake_device.zig");
    const allocator = std.testing.allocator;
    const node = types.UiNode{
        .stable_id = try allocator.dupe(u8, "button"),
        .class_name = try allocator.dupe(u8, "android.widget.Button"),
        .text = try allocator.dupe(u8, "Tap Target"),
        .bounds = .{ .x = 10, .y = 20, .width = 100, .height = 40 },
    };
    const nodes = try allocator.alloc(types.UiNode, 1);
    nodes[0] = node;
    var snapshots = try allocator.alloc(types.ObservationSnapshot, 1);
    snapshots[0] = .{
        .id = try allocator.dupe(u8, "snapshot-settle"),
        .timestamp_ms = 1,
        .nodes = nodes,
    };
    defer {
        snapshots[0].deinit(allocator);
        allocator.free(snapshots);
    }

    var fake = fake_device.FakeDevice.init(allocator, snapshots);
    defer fake.deinit();
    const script = try scenario.parseSlice(allocator,
        \\{
        \\  "name": "settle hook",
        \\  "steps": [
        \\    {"action": "launch"},
        \\    {"action": "openLink", "url": "exampleapp://settle"},
        \\    {"action": "tap", "selector": {"text": "Tap Target"}},
        \\    {"action": "typeText", "text": "hello"},
        \\    {"action": "pressBack"}
        \\  ]
        \\}
    );
    defer script.deinit(allocator);

    try runScenario(allocator, &fake, script, null, .{ .settle_ms = 123, .poll_ms = 0, .action_timeout_ms = 0 });

    try std.testing.expectEqual(@as(usize, 5), fake.settles);
    try std.testing.expectEqual(@as(u64, 123), fake.last_settle_timeout_ms);
}

test "runner timeout diagnostics include selectors active window and visible text" {
    const fake_device = @import("fake_device.zig");
    const allocator = std.testing.allocator;
    const dir = "zig-cache-test-runner-diagnostics";
    std.fs.cwd().deleteTree(dir) catch {};
    defer std.fs.cwd().deleteTree(dir) catch {};

    var snapshots = std.ArrayList(types.ObservationSnapshot).empty;
    defer {
        for (snapshots.items) |snap| snap.deinit(allocator);
        snapshots.deinit(allocator);
    }
    try appendDiagnosticSnapshot(allocator, &snapshots, "diag-any");
    try appendTextSnapshot(allocator, &snapshots, "diag-not-visible", "Still Visible", .{});
    try appendTextSnapshot(allocator, &snapshots, "diag-scroll", "Before Scroll", .{});

    var fake = fake_device.FakeDevice.init(allocator, snapshots.items);
    defer fake.deinit();

    var tw = try trace.TraceWriter.init(allocator, dir);
    defer tw.deinit();

    const selectors = [_]selector.Selector{ .{ .text = "Missing" }, .{ .content_desc_contains = "Other" } };
    try std.testing.expectEqual(@as(?usize, null), try waitUntilAnyVisible(&fake, selectors[0..], 0, &tw, .{ .settle_ms = 0, .poll_ms = 0 }));
    try std.testing.expect(!try waitUntilNotVisible(&fake, .{ .text = "Still Visible" }, 0, &tw, .{ .settle_ms = 0, .poll_ms = 0 }));
    try std.testing.expect(!try scrollUntilVisible(&fake, .{ .text = "Never" }, 0, .down, &tw, .{ .settle_ms = 0, .poll_ms = 0 }));

    const events_path = try std.fs.path.join(allocator, &.{ dir, "events.jsonl" });
    defer allocator.free(events_path);
    const events = try std.fs.cwd().readFileAlloc(allocator, events_path, 1024 * 1024);
    defer allocator.free(events);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"kind\":\"wait.any\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"status\":\"timeout\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"activePackage\":\"com.example.mobiletest\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"activeActivity\":\".MainActivity\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"visibleTexts\":[\"Home\",\"Settings\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"kind\":\"wait.notVisible\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"kind\":\"ui.scrollUntilVisible\"") != null);
}

test "tap diagnostics report hidden disabled offscreen and nearest text candidates" {
    const fake_device = @import("fake_device.zig");
    const allocator = std.testing.allocator;
    const dir = "zig-cache-test-runner-actionable-diagnostics";
    std.fs.cwd().deleteTree(dir) catch {};
    defer std.fs.cwd().deleteTree(dir) catch {};

    const nodes = try allocator.alloc(types.UiNode, 4);
    nodes[0] = .{
        .stable_id = try allocator.dupe(u8, "node-disabled"),
        .class_name = try allocator.dupe(u8, "android.widget.Button"),
        .text = try allocator.dupe(u8, "Sign in"),
        .bounds = .{ .x = 40, .y = 80, .width = 160, .height = 60 },
        .enabled = false,
    };
    nodes[1] = .{
        .stable_id = try allocator.dupe(u8, "node-hidden"),
        .class_name = try allocator.dupe(u8, "android.widget.Button"),
        .text = try allocator.dupe(u8, "Sign in"),
        .bounds = .{ .x = 40, .y = 160, .width = 160, .height = 60 },
        .visible = false,
    };
    nodes[2] = .{
        .stable_id = try allocator.dupe(u8, "node-offscreen"),
        .class_name = try allocator.dupe(u8, "android.widget.Button"),
        .text = try allocator.dupe(u8, "Sign in"),
        .bounds = .{ .x = 40, .y = 1400, .width = 160, .height = 60 },
    };
    nodes[3] = .{
        .stable_id = try allocator.dupe(u8, "node-near"),
        .class_name = try allocator.dupe(u8, "android.widget.Button"),
        .text = try allocator.dupe(u8, "Sign up"),
        .bounds = .{ .x = 40, .y = 260, .width = 160, .height = 60 },
    };

    var snaps = try allocator.alloc(types.ObservationSnapshot, 1);
    snaps[0] = .{
        .id = try allocator.dupe(u8, "diag-actionable"),
        .timestamp_ms = 1,
        .viewport = .{ .width = 720, .height = 1280 },
        .nodes = nodes,
    };
    defer {
        snaps[0].deinit(allocator);
        allocator.free(snaps);
    }

    var fake = fake_device.FakeDevice.init(allocator, snaps);
    defer fake.deinit();

    var tw = try trace.TraceWriter.init(allocator, dir);
    defer tw.deinit();

    try std.testing.expectError(
        error.SelectorNotFound,
        tapSelector(&fake, .{ .text = "Sign in" }, &tw, .{ .settle_ms = 0, .poll_ms = 0, .action_timeout_ms = 0 }),
    );
    try std.testing.expectEqual(@as(usize, 0), fake.taps);

    const events_path = try std.fs.path.join(allocator, &.{ dir, "events.jsonl" });
    defer allocator.free(events_path);
    const events = try std.fs.cwd().readFileAlloc(allocator, events_path, 1024 * 1024);
    defer allocator.free(events);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"kind\":\"ui.tap.notFound\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"disabledCandidates\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"stableId\":\"node-disabled\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"hiddenCandidates\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"stableId\":\"node-hidden\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"offscreenCandidates\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"stableId\":\"node-offscreen\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"nearestTextMatches\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"text\":\"Sign up\"") != null);
}

test "runner records terminal failure events before returning an error" {
    const fake_device = @import("fake_device.zig");
    const allocator = std.testing.allocator;
    const dir = "zig-cache-test-runner-failure-events";
    std.fs.cwd().deleteTree(dir) catch {};
    defer std.fs.cwd().deleteTree(dir) catch {};

    var snapshots = std.ArrayList(types.ObservationSnapshot).empty;
    defer {
        for (snapshots.items) |snap| snap.deinit(allocator);
        snapshots.deinit(allocator);
    }
    try appendTextSnapshot(allocator, &snapshots, "failure-start", "Only visible text", .{});

    var fake = fake_device.FakeDevice.init(allocator, snapshots.items);
    defer fake.deinit();

    var tw = try trace.TraceWriter.init(allocator, dir);
    defer tw.deinit();

    const script_json =
        \\{
        \\  "name": "failing flow",
        \\  "steps": [
        \\    {"action": "waitVisible", "selector": {"text": "Never appears"}, "timeoutMs": 0}
        \\  ]
        \\}
    ;
    const script = try scenario.parseSlice(allocator, script_json);
    defer script.deinit(allocator);

    try std.testing.expectError(
        error.WaitTimeout,
        runScenario(allocator, &fake, script, &tw, .{ .settle_ms = 0, .poll_ms = 0 }),
    );

    const events_path = try std.fs.path.join(allocator, &.{ dir, "events.jsonl" });
    defer allocator.free(events_path);
    const events = try std.fs.cwd().readFileAlloc(allocator, events_path, 1024 * 1024);
    defer allocator.free(events);

    try std.testing.expect(std.mem.indexOf(u8, events, "\"kind\":\"step.error\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"index\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"error\":\"WaitTimeout\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"kind\":\"scenario.end\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, events, "\"status\":\"failed\"") != null);
}

test "runner writes trace manifest for failed scenarios" {
    const allocator = std.testing.allocator;
    const fake_device = @import("fake_device.zig");
    const dir = "zig-cache-test-runner-failure-manifest";
    std.fs.cwd().deleteTree(dir) catch {};
    defer std.fs.cwd().deleteTree(dir) catch {};

    var snapshots = std.ArrayList(types.ObservationSnapshot).empty;
    defer {
        for (snapshots.items) |snap| snap.deinit(allocator);
        snapshots.deinit(allocator);
    }
    try appendTextSnapshot(allocator, &snapshots, "failure-start", "Only visible text", .{});

    var fake = fake_device.FakeDevice.init(allocator, snapshots.items);
    defer fake.deinit();

    var tw = try trace.TraceWriter.init(allocator, dir);
    defer tw.deinit();

    const script_json =
        \\{
        \\  "name": "manifest failure",
        \\  "appId": "com.example.mobiletest",
        \\  "steps": [
        \\    {"action": "waitVisible", "selector": {"text": "Never appears"}, "timeoutMs": 0}
        \\  ]
        \\}
    ;
    const script = try scenario.parseSlice(allocator, script_json);
    defer script.deinit(allocator);

    try std.testing.expectError(
        error.WaitTimeout,
        runScenario(allocator, &fake, script, &tw, .{ .settle_ms = 0, .poll_ms = 0 }),
    );

    const manifest_path = try std.fs.path.join(allocator, &.{ dir, "trace.json" });
    defer allocator.free(manifest_path);
    const manifest = try std.fs.cwd().readFileAlloc(allocator, manifest_path, 1024 * 1024);
    defer allocator.free(manifest);

    try std.testing.expect(std.mem.indexOf(u8, manifest, "\"scenarioName\":\"manifest failure\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "\"appId\":\"com.example.mobiletest\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "\"status\":\"failed\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "\"failedStepIndex\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "\"error\":\"WaitTimeout\"") != null);
}

test "scroll until visible uses default viewport for downward scroll" {
    const fake_device = @import("fake_device.zig");
    const allocator = std.testing.allocator;

    var snapshots = std.ArrayList(types.ObservationSnapshot).empty;
    defer {
        for (snapshots.items) |snap| snap.deinit(allocator);
        snapshots.deinit(allocator);
    }
    try appendTextSnapshot(allocator, &snapshots, "scroll-default-before", "Before", .{});
    try appendTextSnapshot(allocator, &snapshots, "scroll-default-after", "Target", .{});

    var fake = fake_device.FakeDevice.init(allocator, snapshots.items);
    defer fake.deinit();

    try std.testing.expect(try scrollUntilVisible(&fake, .{ .text = "Target" }, 1000, .down, null, .{ .settle_ms = 0, .poll_ms = 0 }));
    try std.testing.expectEqual(@as(usize, 1), fake.swipes);
    try std.testing.expectEqual(@as(i32, 360), fake.last_swipe.?.x1);
    try std.testing.expectEqual(@as(i32, 1024), fake.last_swipe.?.y1);
    try std.testing.expectEqual(@as(i32, 384), fake.last_swipe.?.y2);
}

fn appendTextSnapshot(
    allocator: std.mem.Allocator,
    snapshots: *std.ArrayList(types.ObservationSnapshot),
    id: []const u8,
    text: ?[]const u8,
    viewport: types.Viewport,
) !void {
    const node_count: usize = if (text == null) 0 else 1;
    const nodes = try allocator.alloc(types.UiNode, node_count);
    errdefer allocator.free(nodes);
    if (text) |value| {
        nodes[0] = .{
            .stable_id = try std.fmt.allocPrint(allocator, "node-{s}", .{id}),
            .class_name = try allocator.dupe(u8, "android.widget.TextView"),
            .text = try allocator.dupe(u8, value),
            .bounds = .{ .x = 10, .y = 20, .width = 80, .height = 40 },
        };
    }
    try snapshots.append(allocator, .{
        .id = try allocator.dupe(u8, id),
        .timestamp_ms = @as(i64, @intCast(snapshots.items.len + 1)),
        .viewport = viewport,
        .nodes = nodes,
    });
}

fn appendDiagnosticSnapshot(
    allocator: std.mem.Allocator,
    snapshots: *std.ArrayList(types.ObservationSnapshot),
    id: []const u8,
) !void {
    const nodes = try allocator.alloc(types.UiNode, 3);
    nodes[0] = .{
        .stable_id = try allocator.dupe(u8, "node-home"),
        .class_name = try allocator.dupe(u8, "android.widget.TextView"),
        .text = try allocator.dupe(u8, "Home"),
        .bounds = .{ .x = 1, .y = 1, .width = 10, .height = 10 },
    };
    nodes[1] = .{
        .stable_id = try allocator.dupe(u8, "node-settings"),
        .class_name = try allocator.dupe(u8, "android.widget.ImageButton"),
        .content_desc = try allocator.dupe(u8, "Settings"),
        .bounds = .{ .x = 2, .y = 2, .width = 10, .height = 10 },
    };
    nodes[2] = .{
        .stable_id = try allocator.dupe(u8, "node-hidden"),
        .class_name = try allocator.dupe(u8, "android.widget.TextView"),
        .text = try allocator.dupe(u8, "Hidden"),
        .visible = false,
    };
    try snapshots.append(allocator, .{
        .id = try allocator.dupe(u8, id),
        .timestamp_ms = @as(i64, @intCast(snapshots.items.len + 1)),
        .viewport = .{ .width = 1080, .height = 2400 },
        .active_package = try allocator.dupe(u8, "com.example.mobiletest"),
        .active_activity = try allocator.dupe(u8, ".MainActivity"),
        .nodes = nodes,
    });
}
