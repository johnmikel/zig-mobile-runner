const std = @import("std");

const schema_registry = @import("schema_registry.zig");
const version = @import("version.zig");

pub fn parseJsonFlag(args: []const []const u8) !bool {
    var json = false;
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--json")) {
            json = true;
        } else {
            return error.UnknownFlag;
        }
    }
    return json;
}

pub fn runVersion(allocator: std.mem.Allocator, args: *std.process.ArgIterator) !void {
    const json = try parseArgIterator(allocator, args);
    const stdout = std.fs.File.stdout().deprecatedWriter();
    if (json) return try version.writeJson(stdout);
    try version.writePlain(stdout);
}

pub fn runSchemas(allocator: std.mem.Allocator, args: *std.process.ArgIterator) !void {
    const json = try parseArgIterator(allocator, args);
    const stdout = std.fs.File.stdout().deprecatedWriter();
    if (json) return try schema_registry.writeJson(stdout);
    for (schema_registry.all()) |schema_info| {
        try stdout.print("{s}\t{s}\n", .{ schema_info.name, schema_info.path });
    }
}

fn parseArgIterator(allocator: std.mem.Allocator, args: *std.process.ArgIterator) !bool {
    var raw_args = std.ArrayList([]const u8).empty;
    defer raw_args.deinit(allocator);
    while (args.next()) |arg| try raw_args.append(allocator, arg);
    return parseJsonFlag(raw_args.items);
}
