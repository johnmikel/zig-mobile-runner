const std = @import("std");
const command = @import("command.zig");

pub const Args = struct {
    allocator: std.mem.Allocator,
    argv: std.ArrayList([]const u8) = .empty,
    owned: std.ArrayList([]const u8) = .empty,

    pub fn deinit(self: *Args) void {
        for (self.owned.items) |value| self.allocator.free(value);
        self.owned.deinit(self.allocator);
        self.argv.deinit(self.allocator);
    }

    pub fn items(self: *const Args) []const []const u8 {
        return self.argv.items;
    }

    fn appendLiteral(self: *Args, value: []const u8) !void {
        try self.argv.append(self.allocator, value);
    }

    fn appendOwned(self: *Args, value: []const u8) !void {
        try self.owned.append(self.allocator, value);
        try self.argv.append(self.allocator, value);
    }

    fn appendFmt(self: *Args, comptime fmt: []const u8, values: anytype) !void {
        const value = try std.fmt.allocPrint(self.allocator, fmt, values);
        errdefer self.allocator.free(value);
        try self.appendOwned(value);
    }
};

fn initArgs(allocator: std.mem.Allocator) Args {
    return .{ .allocator = allocator };
}

pub fn openLinkIntent(allocator: std.mem.Allocator, url: []const u8, app_id: []const u8) !Args {
    var args = initArgs(allocator);
    errdefer args.deinit();

    const escaped_url = try command.escapeAdbShellArg(allocator, url);
    errdefer allocator.free(escaped_url);

    try args.appendLiteral("shell");
    try args.appendLiteral("am");
    try args.appendLiteral("start");
    try args.appendLiteral("-a");
    try args.appendLiteral("android.intent.action.VIEW");
    try args.appendLiteral("-d");
    try args.appendOwned(escaped_url);
    try args.appendLiteral(app_id);
    return args;
}

pub fn tap(allocator: std.mem.Allocator, x: i32, y: i32) !Args {
    var args = initArgs(allocator);
    errdefer args.deinit();
    try args.appendLiteral("shell");
    try args.appendLiteral("input");
    try args.appendLiteral("tap");
    try args.appendFmt("{d}", .{x});
    try args.appendFmt("{d}", .{y});
    return args;
}

pub fn typeText(allocator: std.mem.Allocator, text: []const u8) !Args {
    var args = initArgs(allocator);
    errdefer args.deinit();
    const escaped = try command.escapeAdbInputText(allocator, text);
    errdefer allocator.free(escaped);
    try args.appendLiteral("shell");
    try args.appendLiteral("input");
    try args.appendLiteral("text");
    try args.appendOwned(escaped);
    return args;
}

pub fn eraseText(allocator: std.mem.Allocator, max_chars: u32) !Args {
    var args = initArgs(allocator);
    errdefer args.deinit();
    try args.appendLiteral("shell");
    try args.appendLiteral("sh");
    try args.appendLiteral("-c");
    try args.appendFmt("input keyevent KEYCODE_MOVE_END; i=0; while [ $i -lt {d} ]; do input keyevent KEYCODE_DEL; i=$((i+1)); done", .{max_chars});
    return args;
}

pub fn pressBack(allocator: std.mem.Allocator) !Args {
    var args = initArgs(allocator);
    errdefer args.deinit();
    try args.appendLiteral("shell");
    try args.appendLiteral("input");
    try args.appendLiteral("keyevent");
    try args.appendLiteral("BACK");
    return args;
}

pub fn swipe(allocator: std.mem.Allocator, x1: i32, y1: i32, x2: i32, y2: i32, duration_ms: u32) !Args {
    var args = initArgs(allocator);
    errdefer args.deinit();
    try args.appendLiteral("shell");
    try args.appendLiteral("input");
    try args.appendLiteral("swipe");
    try args.appendFmt("{d}", .{x1});
    try args.appendFmt("{d}", .{y1});
    try args.appendFmt("{d}", .{x2});
    try args.appendFmt("{d}", .{y2});
    try args.appendFmt("{d}", .{duration_ms});
    return args;
}
