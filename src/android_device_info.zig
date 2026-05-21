const std = @import("std");
const command = @import("command.zig");
const types = @import("types.zig");

const default_adb_timeout_ms = 15_000;

pub fn listDevices(allocator: std.mem.Allocator, adb_path: []const u8) ![]types.DeviceInfo {
    const result = try command.runWithTimeout(allocator, &.{ adb_path, "devices" }, 1024 * 1024, default_adb_timeout_ms);
    defer result.deinit(allocator);
    try result.ensureSuccess();

    var devices = std.ArrayList(types.DeviceInfo).empty;
    errdefer {
        for (devices.items) |device| device.deinit(allocator);
        devices.deinit(allocator);
    }

    var lines = std.mem.splitScalar(u8, result.stdout, '\n');
    _ = lines.next();
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r\n");
        if (line.len == 0) continue;
        var parts = std.mem.tokenizeAny(u8, line, " \t");
        const serial = parts.next() orelse continue;
        const state = parts.next() orelse continue;
        try devices.append(allocator, .{
            .serial = try allocator.dupe(u8, serial),
            .state = try allocator.dupe(u8, state),
        });
    }

    return try devices.toOwnedSlice(allocator);
}

pub const ActiveWindow = struct {
    package: ?[]const u8 = null,
    activity: ?[]const u8 = null,

    pub fn deinit(self: ActiveWindow, allocator: std.mem.Allocator) void {
        if (self.package) |value| allocator.free(value);
        if (self.activity) |value| allocator.free(value);
    }
};

pub fn parseActiveWindow(allocator: std.mem.Allocator, dumpsys: []const u8) !ActiveWindow {
    const markers = [_][]const u8{ "mCurrentFocus=", "mFocusedApp=", "topResumedActivity=" };
    for (markers) |marker| {
        if (std.mem.indexOf(u8, dumpsys, marker)) |pos| {
            const line_end = std.mem.indexOfScalarPos(u8, dumpsys, pos, '\n') orelse dumpsys.len;
            const line = dumpsys[pos..line_end];
            if (parsePackageActivity(allocator, line)) |active| return active else |_| continue;
        }
    }
    return .{};
}

fn parsePackageActivity(allocator: std.mem.Allocator, line: []const u8) !ActiveWindow {
    const slash = std.mem.indexOfScalar(u8, line, '/') orelse return error.NoActivity;
    var pkg_start = slash;
    while (pkg_start > 0) : (pkg_start -= 1) {
        const ch = line[pkg_start - 1];
        if (!(std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '.')) break;
    }
    var activity_end = slash + 1;
    while (activity_end < line.len) : (activity_end += 1) {
        const ch = line[activity_end];
        if (!(std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '.' or ch == '$')) break;
    }
    if (pkg_start >= slash or activity_end <= slash + 1) return error.NoActivity;
    return .{
        .package = try allocator.dupe(u8, line[pkg_start..slash]),
        .activity = try allocator.dupe(u8, line[slash + 1 .. activity_end]),
    };
}

pub fn parseViewport(output: []const u8) !types.Viewport {
    const marker = "Physical size:";
    const start = std.mem.indexOf(u8, output, marker) orelse return error.NoViewport;
    const after = std.mem.trim(u8, output[start + marker.len ..], " \t\r\n");
    const x = std.mem.indexOfScalar(u8, after, 'x') orelse return error.NoViewport;
    var end: usize = x + 1;
    while (end < after.len and std.ascii.isDigit(after[end])) : (end += 1) {}
    return .{
        .width = try std.fmt.parseInt(u32, std.mem.trim(u8, after[0..x], " \t"), 10),
        .height = try std.fmt.parseInt(u32, after[x + 1 .. end], 10),
    };
}

pub fn parseDisplayDensityDpi(output: []const u8) ?u32 {
    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, " \t\r\n");
        const prefix = "Physical density:";
        if (!std.mem.startsWith(u8, line, prefix)) continue;
        const value = std.mem.trim(u8, line[prefix.len..], " \t\r\n");
        return std.fmt.parseInt(u32, value, 10) catch null;
    }
    return null;
}
