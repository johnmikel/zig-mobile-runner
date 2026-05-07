pub const runner_version = "0.1.0-dev";
pub const protocol_version = "2026-04-28";
pub const protocol_min_compatible_version = "2026-04-28";
pub const protocol_stability = "dev-preview";
pub const protocol_breaking_change_policy = "version-and-changelog";

pub fn writePlain(writer: anytype) !void {
    try writer.print("zmr {s} protocol {s}\n", .{ runner_version, protocol_version });
}

pub fn writeJson(writer: anytype) !void {
    try writer.print(
        "{{\"name\":\"zmr\",\"version\":\"{s}\",\"protocolVersion\":\"{s}\",\"minimumCompatibleProtocolVersion\":\"{s}\",\"stability\":\"{s}\",\"breakingChangePolicy\":\"{s}\"}}\n",
        .{
            runner_version,
            protocol_version,
            protocol_min_compatible_version,
            protocol_stability,
            protocol_breaking_change_policy,
        },
    );
}

test "plain version output includes runner and protocol versions" {
    const std = @import("std");
    var buffer = std.ArrayList(u8).empty;
    defer buffer.deinit(std.testing.allocator);

    try writePlain(buffer.writer(std.testing.allocator));

    try std.testing.expectEqualStrings("zmr 0.1.0-dev protocol 2026-04-28\n", buffer.items);
}

test "json version output includes protocol compatibility metadata" {
    const std = @import("std");
    var buffer = std.ArrayList(u8).empty;
    defer buffer.deinit(std.testing.allocator);

    try writeJson(buffer.writer(std.testing.allocator));

    try std.testing.expectEqualStrings(
        "{\"name\":\"zmr\",\"version\":\"0.1.0-dev\",\"protocolVersion\":\"2026-04-28\",\"minimumCompatibleProtocolVersion\":\"2026-04-28\",\"stability\":\"dev-preview\",\"breakingChangePolicy\":\"version-and-changelog\"}\n",
        buffer.items,
    );
}

test "protocol compatibility policy is explicit for clients" {
    const std = @import("std");
    try std.testing.expectEqualStrings("2026-04-28", protocol_min_compatible_version);
    try std.testing.expectEqualStrings("dev-preview", protocol_stability);
    try std.testing.expectEqualStrings("version-and-changelog", protocol_breaking_change_policy);
}
