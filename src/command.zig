const std = @import("std");
const builtin = @import("builtin");

pub const ExecResult = struct {
    stdout: []u8,
    stderr: []u8,
    term: std.process.Child.Term,
    timed_out: bool = false,

    pub fn deinit(self: ExecResult, allocator: std.mem.Allocator) void {
        allocator.free(self.stdout);
        allocator.free(self.stderr);
    }

    pub fn ensureSuccess(self: ExecResult) !void {
        if (self.timed_out) return error.CommandTimedOut;
        switch (self.term) {
            .Exited => |code| if (code == 0) return,
            else => {},
        }
        return error.CommandFailed;
    }
};

pub fn run(
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    max_output_bytes: usize,
) !ExecResult {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
        .max_output_bytes = max_output_bytes,
    });
    return .{
        .stdout = result.stdout,
        .stderr = result.stderr,
        .term = result.term,
        .timed_out = false,
    };
}

pub fn runWithInput(
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    stdin: []const u8,
    max_output_bytes: usize,
) !ExecResult {
    return try runWithInputTimeout(allocator, argv, stdin, max_output_bytes, 0);
}

pub fn runWithInputTimeout(
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    stdin: []const u8,
    max_output_bytes: usize,
    timeout_ms: u64,
) !ExecResult {
    var child = std.process.Child.init(argv, allocator);
    child.stdin_behavior = .Pipe;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    var stdout = std.ArrayList(u8).empty;
    defer stdout.deinit(allocator);
    var stderr = std.ArrayList(u8).empty;
    defer stderr.deinit(allocator);

    try child.spawn();
    errdefer _ = child.kill() catch {};

    var done = std.Thread.ResetEvent{};
    var timed_out = std.atomic.Value(bool).init(false);
    const use_timeout = timeout_ms > 0;
    const killer = if (use_timeout)
        try std.Thread.spawn(.{}, timeoutKiller, .{
            child.id,
            &done,
            &timed_out,
            std.math.mul(u64, timeout_ms, std.time.ns_per_ms) catch std.math.maxInt(u64),
        })
    else
        null;

    if (child.stdin) |stdin_file| {
        try stdin_file.writeAll(stdin);
        stdin_file.close();
        child.stdin = null;
    }

    child.collectOutput(allocator, &stdout, &stderr, max_output_bytes) catch |err| {
        _ = child.kill() catch {};
        done.set();
        if (killer) |thread| thread.join();
        return err;
    };

    const term = child.wait() catch |err| {
        done.set();
        if (killer) |thread| thread.join();
        return err;
    };
    done.set();
    if (killer) |thread| thread.join();

    return .{
        .stdout = try stdout.toOwnedSlice(allocator),
        .stderr = try stderr.toOwnedSlice(allocator),
        .term = term,
        .timed_out = timed_out.load(.acquire),
    };
}

pub fn runWithTimeout(
    allocator: std.mem.Allocator,
    argv: []const []const u8,
    max_output_bytes: usize,
    timeout_ms: u64,
) !ExecResult {
    if (timeout_ms == 0) return run(allocator, argv, max_output_bytes);

    var child = std.process.Child.init(argv, allocator);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    var stdout = std.ArrayList(u8).empty;
    defer stdout.deinit(allocator);
    var stderr = std.ArrayList(u8).empty;
    defer stderr.deinit(allocator);

    try child.spawn();
    errdefer _ = child.kill() catch {};

    var done = std.Thread.ResetEvent{};
    var timed_out = std.atomic.Value(bool).init(false);
    const timeout_ns = std.math.mul(u64, timeout_ms, std.time.ns_per_ms) catch std.math.maxInt(u64);
    const killer = try std.Thread.spawn(.{}, timeoutKiller, .{ child.id, &done, &timed_out, timeout_ns });

    child.collectOutput(allocator, &stdout, &stderr, max_output_bytes) catch |err| {
        _ = child.kill() catch {};
        done.set();
        killer.join();
        return err;
    };

    const term = child.wait() catch |err| {
        done.set();
        killer.join();
        return err;
    };
    done.set();
    killer.join();

    return .{
        .stdout = try stdout.toOwnedSlice(allocator),
        .stderr = try stderr.toOwnedSlice(allocator),
        .term = term,
        .timed_out = timed_out.load(.acquire),
    };
}

fn timeoutKiller(
    child_id: std.process.Child.Id,
    done: *std.Thread.ResetEvent,
    timed_out: *std.atomic.Value(bool),
    timeout_ns: u64,
) void {
    done.timedWait(timeout_ns) catch {
        timed_out.store(true, .release);
        killChildId(child_id);
    };
}

fn killChildId(child_id: std.process.Child.Id) void {
    switch (builtin.os.tag) {
        .windows => {},
        else => std.posix.kill(child_id, std.posix.SIG.TERM) catch {},
    }
}

pub fn escapeAdbInputText(allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    for (text) |ch| {
        switch (ch) {
            ' ' => try out.appendSlice(allocator, "%s"),
            '&', '<', '>', ';', '|', '*', '~', '"', '\'', '\\', '(', ')' => {
                try out.append(allocator, '\\');
                try out.append(allocator, ch);
            },
            else => try out.append(allocator, ch),
        }
    }
    return try out.toOwnedSlice(allocator);
}

pub fn escapeAdbShellArg(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    try out.append(allocator, '\'');
    for (value) |ch| {
        if (ch == '\'') {
            try out.appendSlice(allocator, "'\\''");
        } else {
            try out.append(allocator, ch);
        }
    }
    try out.append(allocator, '\'');
    return try out.toOwnedSlice(allocator);
}
