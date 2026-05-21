const std = @import("std");

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

pub const ImportedScenario = struct {
    name: []const u8,
    app_id: ?[]const u8 = null,
    steps: []ImportedStep,

    pub fn deinit(self: ImportedScenario, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.app_id) |value| allocator.free(value);
        for (self.steps) |step| step.deinit(allocator);
        allocator.free(self.steps);
    }
};

pub const SelectorSpec = struct {
    id: ?[]const u8 = null,
    text: ?[]const u8 = null,
    text_contains: ?[]const u8 = null,
    content_desc: ?[]const u8 = null,

    pub fn deinit(self: SelectorSpec, allocator: std.mem.Allocator) void {
        if (self.id) |value| allocator.free(value);
        if (self.text) |value| allocator.free(value);
        if (self.text_contains) |value| allocator.free(value);
        if (self.content_desc) |value| allocator.free(value);
    }

    pub fn hasAny(self: SelectorSpec) bool {
        return self.id != null or self.text != null or self.text_contains != null or self.content_desc != null;
    }
};

pub const WaitSelector = struct {
    selector: SelectorSpec,
    timeout_ms: u64 = 5000,

    pub fn deinit(self: WaitSelector, allocator: std.mem.Allocator) void {
        self.selector.deinit(allocator);
    }
};

pub const ScrollStep = struct {
    selector: SelectorSpec,
    direction: []const u8 = "down",
    timeout_ms: u64 = 5000,

    pub fn deinit(self: ScrollStep, allocator: std.mem.Allocator) void {
        self.selector.deinit(allocator);
    }
};

pub const ImportedStep = union(enum) {
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

    pub fn deinit(self: ImportedStep, allocator: std.mem.Allocator) void {
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
