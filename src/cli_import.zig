const std = @import("std");

const cli_output = @import("cli_output.zig");
const importer = @import("importer.zig");

pub const ParsedArgs = struct {
    format: []const u8,
    source_path: []const u8,
    out_path: ?[]const u8 = null,
    name: ?[]const u8 = null,
    app_id: ?[]const u8 = null,
    force: bool = false,
    json: bool = false,
};

pub fn parseArgs(args: []const []const u8) !ParsedArgs {
    if (args.len == 0) return error.MissingImportFormat;
    if (args.len == 1) return error.MissingImportPath;

    var parsed = ParsedArgs{
        .format = args[0],
        .source_path = args[1],
    };

    var index: usize = 2;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--out")) {
            index += 1;
            parsed.out_path = if (index < args.len) args[index] else return error.MissingImportOut;
        } else if (std.mem.eql(u8, arg, "--name")) {
            index += 1;
            parsed.name = if (index < args.len) args[index] else return error.MissingImportName;
        } else if (std.mem.eql(u8, arg, "--app-id")) {
            index += 1;
            parsed.app_id = if (index < args.len) args[index] else return error.MissingAppId;
        } else if (std.mem.eql(u8, arg, "--force")) {
            parsed.force = true;
        } else if (std.mem.eql(u8, arg, "--json")) {
            parsed.json = true;
        } else {
            return error.UnknownFlag;
        }
    }
    if (parsed.out_path == null) return error.MissingImportOut;
    return parsed;
}

pub fn run(allocator: std.mem.Allocator, args: *std.process.ArgIterator) !void {
    var raw_args = std.ArrayList([]const u8).empty;
    defer raw_args.deinit(allocator);
    while (args.next()) |arg| try raw_args.append(allocator, arg);

    const parsed = try parseArgs(raw_args.items);
    if (!std.mem.eql(u8, parsed.format, "flow-yaml")) return error.UnsupportedImportFormat;

    const result = try importer.importFlowYamlFile(allocator, parsed.source_path, parsed.out_path.?, .{
        .name = parsed.name,
        .app_id = parsed.app_id,
        .force = parsed.force,
    });
    defer result.deinit(allocator);

    const stdout = std.fs.File.stdout().deprecatedWriter();
    if (parsed.json) return try cli_output.writeImportJson(stdout, parsed.format, parsed.source_path, result);
    try stdout.print("wrote {s}\n", .{result.out_path});
    try stdout.writeAll("next: zmr validate ");
    try cli_output.writeShellArg(stdout, result.out_path);
    try stdout.writeAll("\n");
}
