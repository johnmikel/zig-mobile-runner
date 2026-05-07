const std = @import("std");
const selector = @import("selector.zig");

pub const Swipe = struct {
    x1: i32,
    y1: i32,
    x2: i32,
    y2: i32,
    duration_ms: u32 = 300,
};

pub const WaitVisible = struct {
    selector: selector.Selector,
    timeout_ms: u64 = 5000,
};

pub const WaitAny = struct {
    selectors: []selector.Selector,
    timeout_ms: u64 = 5000,

    pub fn deinit(self: WaitAny, allocator: std.mem.Allocator) void {
        for (self.selectors) |wanted| wanted.deinit(allocator);
        allocator.free(self.selectors);
    }
};

pub const TypeText = struct {
    selector: ?selector.Selector = null,
    text: []const u8,

    pub fn deinit(self: TypeText, allocator: std.mem.Allocator) void {
        if (self.selector) |wanted| wanted.deinit(allocator);
        allocator.free(self.text);
    }
};

pub const EraseText = struct {
    selector: ?selector.Selector = null,
    max_chars: u32 = 80,

    pub fn deinit(self: EraseText, allocator: std.mem.Allocator) void {
        if (self.selector) |wanted| wanted.deinit(allocator);
    }
};

pub const StepBlock = struct {
    steps: []Step,

    pub fn deinit(self: StepBlock, allocator: std.mem.Allocator) void {
        for (self.steps) |step| step.deinit(allocator);
        allocator.free(self.steps);
    }
};

pub const ConditionalBlock = struct {
    selector: selector.Selector,
    timeout_ms: u64 = 0,
    steps: []Step,

    pub fn deinit(self: ConditionalBlock, allocator: std.mem.Allocator) void {
        self.selector.deinit(allocator);
        for (self.steps) |step| step.deinit(allocator);
        allocator.free(self.steps);
    }
};

pub const RepeatBlock = struct {
    times: u32,
    steps: []Step,

    pub fn deinit(self: RepeatBlock, allocator: std.mem.Allocator) void {
        for (self.steps) |step| step.deinit(allocator);
        allocator.free(self.steps);
    }
};

pub const ScrollDirection = enum {
    down,
    up,
};

pub const ScrollUntilVisible = struct {
    selector: selector.Selector,
    timeout_ms: u64 = 5000,
    direction: ScrollDirection = .down,

    pub fn deinit(self: ScrollUntilVisible, allocator: std.mem.Allocator) void {
        self.selector.deinit(allocator);
    }
};

pub const Step = union(enum) {
    launch,
    stop,
    clear_state,
    snapshot,
    open_link: []const u8,
    tap: selector.Selector,
    type_text: TypeText,
    press_back,
    hide_keyboard,
    swipe: Swipe,
    erase_text: EraseText,
    wait_visible: WaitVisible,
    wait_not_visible: WaitVisible,
    wait_any: WaitAny,
    assert_visible: selector.Selector,
    assert_not_visible: selector.Selector,
    optional: *Step,
    when_visible: ConditionalBlock,
    repeat: RepeatBlock,
    scroll_until_visible: ScrollUntilVisible,
    sleep_ms: u64,

    pub fn deinit(self: Step, allocator: std.mem.Allocator) void {
        switch (self) {
            .open_link => |value| allocator.free(value),
            .tap => |value| value.deinit(allocator),
            .type_text => |value| value.deinit(allocator),
            .erase_text => |value| value.deinit(allocator),
            .wait_visible => |value| value.selector.deinit(allocator),
            .wait_not_visible => |value| value.selector.deinit(allocator),
            .wait_any => |value| value.deinit(allocator),
            .assert_visible => |value| value.deinit(allocator),
            .assert_not_visible => |value| value.deinit(allocator),
            .optional => |value| {
                value.deinit(allocator);
                allocator.destroy(value);
            },
            .when_visible => |value| value.deinit(allocator),
            .repeat => |value| value.deinit(allocator),
            .scroll_until_visible => |value| value.deinit(allocator),
            else => {},
        }
    }
};

pub const Scenario = struct {
    name: []const u8,
    app_id: ?[]const u8 = null,
    steps: []Step,

    pub fn deinit(self: Scenario, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.app_id) |value| allocator.free(value);
        for (self.steps) |step| step.deinit(allocator);
        allocator.free(self.steps);
    }
};

pub fn parseFile(allocator: std.mem.Allocator, path: []const u8) !Scenario {
    const content = try std.fs.cwd().readFileAlloc(allocator, path, 16 * 1024 * 1024);
    defer allocator.free(content);
    return try parseSlice(allocator, content);
}

pub fn parseSlice(allocator: std.mem.Allocator, content: []const u8) !Scenario {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, content, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.ScenarioMustBeObject;
    const root = parsed.value.object;

    const name = try requiredString(allocator, root, "name");
    errdefer allocator.free(name);
    const app_id = try optionalString(allocator, root, "appId");
    errdefer if (app_id) |value| allocator.free(value);

    const steps_value = root.get("steps") orelse return error.ScenarioMissingSteps;
    if (steps_value != .array) return error.ScenarioStepsMustBeArray;
    var steps = std.ArrayList(Step).empty;
    errdefer {
        for (steps.items) |step| step.deinit(allocator);
        steps.deinit(allocator);
    }
    try appendParsedSteps(allocator, &steps, steps_value);

    return .{
        .name = name,
        .app_id = app_id,
        .steps = try steps.toOwnedSlice(allocator),
    };
}

fn parseStep(allocator: std.mem.Allocator, value: std.json.Value) anyerror!Step {
    if (value != .object) return error.StepMustBeObject;
    const object = value.object;
    var parsed = try parseRawStep(allocator, object);
    errdefer parsed.deinit(allocator);

    if (try optionalBool(object, "optional", false)) {
        const step_ptr = try allocator.create(Step);
        errdefer allocator.destroy(step_ptr);
        step_ptr.* = parsed;
        return .{ .optional = step_ptr };
    }

    return parsed;
}

fn parseRawStep(allocator: std.mem.Allocator, object: std.json.ObjectMap) anyerror!Step {
    const action_value = object.get("action") orelse return error.StepMissingAction;
    if (action_value != .string) return error.StepActionMustBeString;
    const action = action_value.string;

    if (std.mem.eql(u8, action, "launch")) return .launch;
    if (std.mem.eql(u8, action, "stop")) return .stop;
    if (std.mem.eql(u8, action, "clearState")) return .clear_state;
    if (std.mem.eql(u8, action, "snapshot")) return .snapshot;
    if (std.mem.eql(u8, action, "pressBack")) return .press_back;
    if (std.mem.eql(u8, action, "hideKeyboard")) return .hide_keyboard;
    if (std.mem.eql(u8, action, "sleep")) return .{ .sleep_ms = try optionalU64(object, "ms", 500) };
    if (std.mem.eql(u8, action, "openLink")) return .{ .open_link = try requiredStringOrError(allocator, object, "url", error.StepMissingUrl) };
    if (std.mem.eql(u8, action, "tap")) return .{ .tap = try parseSelectorField(allocator, object) };
    if (std.mem.eql(u8, action, "typeText")) {
        const wanted = if (object.get("selector")) |selector_value| try selector.parseFromJson(allocator, selector_value) else null;
        errdefer if (wanted) |actual| actual.deinit(allocator);
        return .{ .type_text = .{
            .selector = wanted,
            .text = try requiredStringOrError(allocator, object, "text", error.StepMissingText),
        } };
    }
    if (std.mem.eql(u8, action, "eraseText")) {
        const wanted = if (object.get("selector")) |selector_value| try selector.parseFromJson(allocator, selector_value) else null;
        errdefer if (wanted) |actual| actual.deinit(allocator);
        return .{ .erase_text = .{
            .selector = wanted,
            .max_chars = @as(u32, @intCast(try optionalU64(object, "maxChars", 80))),
        } };
    }
    if (std.mem.eql(u8, action, "swipe")) return .{ .swipe = .{
        .x1 = try requiredI32OrError(object, "x1", error.StepMissingX1),
        .y1 = try requiredI32OrError(object, "y1", error.StepMissingY1),
        .x2 = try requiredI32OrError(object, "x2", error.StepMissingX2),
        .y2 = try requiredI32OrError(object, "y2", error.StepMissingY2),
        .duration_ms = @as(u32, @intCast(try optionalU64(object, "durationMs", 300))),
    } };
    if (std.mem.eql(u8, action, "waitVisible")) {
        const wanted = try parseSelectorField(allocator, object);
        errdefer wanted.deinit(allocator);
        return .{ .wait_visible = .{
            .selector = wanted,
            .timeout_ms = try optionalU64(object, "timeoutMs", 5000),
        } };
    }
    if (std.mem.eql(u8, action, "waitNotVisible")) {
        const wanted = try parseSelectorField(allocator, object);
        errdefer wanted.deinit(allocator);
        return .{ .wait_not_visible = .{
            .selector = wanted,
            .timeout_ms = try optionalU64(object, "timeoutMs", 5000),
        } };
    }
    if (std.mem.eql(u8, action, "waitAny")) {
        const selectors = try parseSelectorArrayField(allocator, object);
        errdefer {
            for (selectors) |wanted| wanted.deinit(allocator);
            allocator.free(selectors);
        }
        return .{ .wait_any = .{
            .selectors = selectors,
            .timeout_ms = try optionalU64(object, "timeoutMs", 5000),
        } };
    }
    if (std.mem.eql(u8, action, "assertVisible")) return .{ .assert_visible = try parseSelectorField(allocator, object) };
    if (std.mem.eql(u8, action, "assertNotVisible")) return .{ .assert_not_visible = try parseSelectorField(allocator, object) };
    if (std.mem.eql(u8, action, "optional")) {
        const nested_value = object.get("step") orelse return error.OptionalStepMissingStep;
        const nested = try allocator.create(Step);
        errdefer allocator.destroy(nested);
        nested.* = try parseStep(allocator, nested_value);
        return .{ .optional = nested };
    }
    if (std.mem.eql(u8, action, "whenVisible")) {
        const wanted = try parseSelectorField(allocator, object);
        errdefer wanted.deinit(allocator);
        const timeout_ms = try optionalU64(object, "timeoutMs", 0);
        const steps = try parseStepsField(allocator, object);
        errdefer {
            for (steps) |step| step.deinit(allocator);
            allocator.free(steps);
        }
        return .{ .when_visible = .{
            .selector = wanted,
            .timeout_ms = timeout_ms,
            .steps = steps,
        } };
    }
    if (std.mem.eql(u8, action, "repeat")) return .{ .repeat = .{
        .times = @as(u32, @intCast(try optionalU64(object, "times", 1))),
        .steps = try parseStepsField(allocator, object),
    } };
    if (std.mem.eql(u8, action, "scrollUntilVisible")) {
        const wanted = try parseSelectorField(allocator, object);
        errdefer wanted.deinit(allocator);
        return .{ .scroll_until_visible = .{
            .selector = wanted,
            .timeout_ms = try optionalU64(object, "timeoutMs", 5000),
            .direction = try optionalDirection(object, "direction", .down),
        } };
    }

    return error.UnknownScenarioAction;
}

fn appendParsedSteps(allocator: std.mem.Allocator, steps: *std.ArrayList(Step), value: std.json.Value) anyerror!void {
    if (value != .array) return error.ScenarioStepsMustBeArray;
    for (value.array.items) |step_value| {
        try steps.append(allocator, try parseStep(allocator, step_value));
    }
}

fn parseStepsField(allocator: std.mem.Allocator, object: std.json.ObjectMap) anyerror![]Step {
    const steps_value = object.get("steps") orelse return error.StepBlockMissingSteps;
    if (steps_value != .array) return error.StepBlockStepsMustBeArray;
    var steps = std.ArrayList(Step).empty;
    errdefer {
        for (steps.items) |step| step.deinit(allocator);
        steps.deinit(allocator);
    }
    try appendParsedSteps(allocator, &steps, steps_value);
    return try steps.toOwnedSlice(allocator);
}

fn parseSelectorField(allocator: std.mem.Allocator, object: std.json.ObjectMap) !selector.Selector {
    const selector_value = object.get("selector") orelse return error.StepMissingSelector;
    return try selector.parseFromJson(allocator, selector_value);
}

fn parseSelectorArrayField(allocator: std.mem.Allocator, object: std.json.ObjectMap) ![]selector.Selector {
    const selectors_value = object.get("selectors") orelse return error.StepMissingSelectors;
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

fn requiredString(allocator: std.mem.Allocator, object: std.json.ObjectMap, key: []const u8) ![]const u8 {
    const value = object.get(key) orelse return error.RequiredStringMissing;
    if (value != .string) return error.RequiredFieldMustBeString;
    return try allocator.dupe(u8, value.string);
}

fn requiredStringOrError(allocator: std.mem.Allocator, object: std.json.ObjectMap, key: []const u8, missing_error: anyerror) ![]const u8 {
    const value = object.get(key) orelse return missing_error;
    if (value != .string) return error.RequiredFieldMustBeString;
    return try allocator.dupe(u8, value.string);
}

fn optionalString(allocator: std.mem.Allocator, object: std.json.ObjectMap, key: []const u8) !?[]const u8 {
    const value = object.get(key) orelse return null;
    if (value != .string) return error.OptionalFieldMustBeString;
    return try allocator.dupe(u8, value.string);
}

fn requiredI32(object: std.json.ObjectMap, key: []const u8) !i32 {
    const value = object.get(key) orelse return error.RequiredIntegerMissing;
    return switch (value) {
        .integer => |actual| @as(i32, @intCast(actual)),
        else => error.RequiredFieldMustBeInteger,
    };
}

fn requiredI32OrError(object: std.json.ObjectMap, key: []const u8, missing_error: anyerror) !i32 {
    const value = object.get(key) orelse return missing_error;
    return switch (value) {
        .integer => |actual| @as(i32, @intCast(actual)),
        else => error.RequiredFieldMustBeInteger,
    };
}

fn optionalU64(object: std.json.ObjectMap, key: []const u8, default_value: u64) !u64 {
    const value = object.get(key) orelse return default_value;
    return switch (value) {
        .integer => |actual| @as(u64, @intCast(actual)),
        else => error.OptionalFieldMustBeInteger,
    };
}

fn optionalBool(object: std.json.ObjectMap, key: []const u8, default_value: bool) !bool {
    const value = object.get(key) orelse return default_value;
    return switch (value) {
        .bool => |actual| actual,
        else => error.OptionalFieldMustBeBool,
    };
}

fn optionalDirection(object: std.json.ObjectMap, key: []const u8, default_value: ScrollDirection) !ScrollDirection {
    const value = object.get(key) orelse return default_value;
    if (value != .string) return error.OptionalFieldMustBeString;
    if (std.mem.eql(u8, value.string, "down")) return .down;
    if (std.mem.eql(u8, value.string, "up")) return .up;
    return error.UnknownScrollDirection;
}

test "parse scenario with open link and wait" {
    const json =
        \\{
        \\  "name": "probe",
        \\  "appId": "com.example.mobiletest",
        \\  "steps": [
        \\    {"action": "openLink", "url": "exampleapp://e2e-auth?probe=1"},
        \\    {"action": "waitVisible", "selector": {"text": "E2E auth probe"}, "timeoutMs": 30000}
        \\  ]
        \\}
    ;
    const parsed = try parseSlice(std.testing.allocator, json);
    defer parsed.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("probe", parsed.name);
    try std.testing.expectEqual(@as(usize, 2), parsed.steps.len);
    try std.testing.expectEqualStrings("com.example.mobiletest", parsed.app_id.?);
}

test "parse agent-grade flow primitives" {
    const json =
        \\{
        \\  "name": "flow",
        \\  "steps": [
        \\    {"action": "waitAny", "selectors": [{"text": "A"}, {"textContains": "B"}], "timeoutMs": 10},
        \\    {"action": "whenVisible", "selector": {"text": "A"}, "steps": [
        \\      {"action": "tap", "selector": {"text": "A"}, "optional": true}
        \\    ]},
        \\    {"action": "repeat", "times": 2, "steps": [
        \\      {"action": "eraseText", "maxChars": 5},
        \\      {"action": "hideKeyboard"}
        \\    ]},
        \\    {"action": "scrollUntilVisible", "selector": {"id": "target"}, "direction": "down"}
        \\  ]
        \\}
    ;
    const parsed = try parseSlice(std.testing.allocator, json);
    defer parsed.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 4), parsed.steps.len);
    try std.testing.expectEqual(@as(usize, 2), parsed.steps[0].wait_any.selectors.len);
    try std.testing.expectEqual(@as(u32, 2), parsed.steps[2].repeat.times);
}

test "parse all simple action variants" {
    const json =
        \\{
        \\  "name": "all actions",
        \\  "steps": [
        \\    {"action": "launch"},
        \\    {"action": "stop"},
        \\    {"action": "clearState"},
        \\    {"action": "snapshot"},
        \\    {"action": "pressBack"},
        \\    {"action": "sleep", "ms": 7},
        \\    {"action": "tap", "selector": {"id": "tap-id"}},
        \\    {"action": "typeText", "text": "hello"},
        \\    {"action": "swipe", "x1": 1, "y1": 2, "x2": 3, "y2": 4},
        \\    {"action": "waitNotVisible", "selector": {"text": "Gone"}},
        \\    {"action": "assertVisible", "selector": {"contentDesc": "Visible"}},
        \\    {"action": "assertNotVisible", "selector": {"className": "android.widget.Toast"}},
        \\    {"action": "scrollUntilVisible", "selector": {"text": "Target"}, "direction": "up"}
        \\  ]
        \\}
    ;
    const parsed = try parseSlice(std.testing.allocator, json);
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(std.meta.Tag(Step), .launch), std.meta.activeTag(parsed.steps[0]));
    try std.testing.expectEqual(@as(std.meta.Tag(Step), .stop), std.meta.activeTag(parsed.steps[1]));
    try std.testing.expectEqual(@as(std.meta.Tag(Step), .clear_state), std.meta.activeTag(parsed.steps[2]));
    try std.testing.expectEqual(@as(std.meta.Tag(Step), .snapshot), std.meta.activeTag(parsed.steps[3]));
    try std.testing.expectEqual(@as(std.meta.Tag(Step), .press_back), std.meta.activeTag(parsed.steps[4]));
    try std.testing.expectEqual(@as(u64, 7), parsed.steps[5].sleep_ms);
    try std.testing.expectEqualStrings("tap-id", parsed.steps[6].tap.id.?);
    try std.testing.expectEqualStrings("hello", parsed.steps[7].type_text.text);
    try std.testing.expectEqual(@as(u32, 300), parsed.steps[8].swipe.duration_ms);
    try std.testing.expectEqualStrings("Gone", parsed.steps[9].wait_not_visible.selector.text.?);
    try std.testing.expectEqualStrings("Visible", parsed.steps[10].assert_visible.content_desc.?);
    try std.testing.expectEqualStrings("android.widget.Toast", parsed.steps[11].assert_not_visible.class_name.?);
    try std.testing.expectEqual(ScrollDirection.up, parsed.steps[12].scroll_until_visible.direction);
}

test "scenario parser rejects malformed input precisely" {
    const allocator = std.testing.allocator;
    try std.testing.expectError(error.ScenarioMustBeObject, parseSlice(allocator, "[]"));
    try std.testing.expectError(error.ScenarioMissingSteps, parseSlice(allocator,
        \\{"name":"missing steps"}
    ));
    try std.testing.expectError(error.ScenarioStepsMustBeArray, parseSlice(allocator,
        \\{"name":"bad steps","steps":{}}
    ));
    try std.testing.expectError(error.StepMissingAction, parseSlice(allocator,
        \\{"name":"bad step","steps":[{}]}
    ));
    try std.testing.expectError(error.StepActionMustBeString, parseSlice(allocator,
        \\{"name":"bad action","steps":[{"action":1}]}
    ));
    try std.testing.expectError(error.SelectorsMustNotBeEmpty, parseSlice(allocator,
        \\{"name":"empty selectors","steps":[{"action":"waitAny","selectors":[]}]}
    ));
    try std.testing.expectError(error.OptionalFieldMustBeBool, parseSlice(allocator,
        \\{"name":"bad optional","steps":[{"action":"tap","selector":{"text":"A"},"optional":"yes"}]}
    ));
    try std.testing.expectError(error.UnknownScrollDirection, parseSlice(allocator,
        \\{"name":"bad direction","steps":[{"action":"scrollUntilVisible","selector":{"text":"A"},"direction":"sideways"}]}
    ));
    try std.testing.expectError(error.UnknownScenarioAction, parseSlice(allocator,
        \\{"name":"unknown","steps":[{"action":"pinch"}]}
    ));
}
