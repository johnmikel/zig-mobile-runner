const std = @import("std");

pub fn writeFile(
    allocator: std.mem.Allocator,
    trace_dir: []const u8,
    archive_path: []const u8,
    out_file: *std.fs.File,
) !void {
    if (isUnsafeArchivePath(archive_path)) return error.UnsafeArchivePath;
    const fs_path = try std.fs.path.join(allocator, &.{ trace_dir, archive_path });
    defer allocator.free(fs_path);

    var in_file = try std.fs.cwd().openFile(fs_path, .{});
    defer in_file.close();
    const stat = try in_file.stat();

    var header = [_]u8{0} ** 512;
    try writeHeader(&header, archive_path, stat.size);

    try out_file.writeAll(&header);
    var buffer: [16 * 1024]u8 = undefined;
    var remaining = stat.size;
    while (remaining > 0) {
        const read_len = @min(buffer.len, remaining);
        const n = try in_file.read(buffer[0..read_len]);
        if (n == 0) return error.UnexpectedEndOfStream;
        try out_file.writeAll(buffer[0..n]);
        remaining -= n;
    }
    try writePadding(out_file, stat.size);
}

pub fn writeBytes(archive_path: []const u8, bytes: []const u8, out_file: *std.fs.File) !void {
    if (isUnsafeArchivePath(archive_path)) return error.UnsafeArchivePath;
    var header = [_]u8{0} ** 512;
    try writeHeader(&header, archive_path, bytes.len);

    try out_file.writeAll(&header);
    try out_file.writeAll(bytes);
    try writePadding(out_file, bytes.len);
}

fn writeHeader(header: *[512]u8, archive_path: []const u8, size: u64) !void {
    try writeTarName(header, archive_path);
    writeOctal(header[100..108], 0o644);
    writeOctal(header[108..116], 0);
    writeOctal(header[116..124], 0);
    writeOctal(header[124..136], size);
    writeOctal(header[136..148], 0);
    @memset(header[148..156], ' ');
    header[156] = '0';
    @memcpy(header[257..263], "ustar\x00");
    @memcpy(header[263..265], "00");
    writeOctal(header[329..337], 0);
    writeOctal(header[337..345], 0);
    const checksum = tarChecksum(header);
    writeChecksum(header[148..156], checksum);
}

fn writePadding(out_file: *std.fs.File, size: u64) !void {
    const padding = (512 - (size % 512)) % 512;
    if (padding > 0) try out_file.writeAll((&([_]u8{0} ** 512))[0..padding]);
}

fn isUnsafeArchivePath(archive_path: []const u8) bool {
    return std.mem.startsWith(u8, archive_path, "/") or std.mem.indexOf(u8, archive_path, "..") != null;
}

fn writeTarName(header: *[512]u8, archive_path: []const u8) !void {
    if (archive_path.len <= 100) {
        @memcpy(header[0..archive_path.len], archive_path);
        return;
    }

    var split_index: ?usize = null;
    var index: usize = archive_path.len;
    while (index > 0) {
        index -= 1;
        if (archive_path[index] != '/') continue;
        const prefix = archive_path[0..index];
        const name = archive_path[index + 1 ..];
        if (prefix.len <= 155 and name.len <= 100) {
            split_index = index;
            break;
        }
    }
    const actual_split = split_index orelse return error.ArchivePathTooLong;
    const prefix = archive_path[0..actual_split];
    const name = archive_path[actual_split + 1 ..];
    @memcpy(header[0..name.len], name);
    @memcpy(header[345 .. 345 + prefix.len], prefix);
}

fn writeOctal(field: []u8, value: u64) void {
    @memset(field, 0);
    const digits_len = field.len - 1;
    var remaining = value;
    var index = digits_len;
    while (index > 0) {
        index -= 1;
        field[index] = @as(u8, @intCast('0' + (remaining & 7)));
        remaining >>= 3;
    }
}

fn writeChecksum(field: []u8, value: u64) void {
    @memset(field, 0);
    var remaining = value;
    var index: usize = 6;
    while (index > 0) {
        index -= 1;
        field[index] = @as(u8, @intCast('0' + (remaining & 7)));
        remaining >>= 3;
    }
    field[6] = 0;
    field[7] = ' ';
}

fn tarChecksum(header: *const [512]u8) u64 {
    var sum: u64 = 0;
    for (header) |byte| sum += byte;
    return sum;
}
