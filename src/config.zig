const std = @import("std");

pub const PlatformConfig = struct {
    enabled: bool = false,
    default_device: ?[]const u8 = null,
    smoke_scenario: ?[]const u8 = null,
    trace_dir: ?[]const u8 = null,
    avd_name: ?[]const u8 = null,
    restore_snapshot: ?[]const u8 = null,
    avd_system_image: ?[]const u8 = null,
    avd_device_profile: ?[]const u8 = null,
    reset_before_run: bool = false,
    wait_ready: bool = false,
    create_avd_if_missing: bool = false,

    pub fn deinit(self: *PlatformConfig, allocator: std.mem.Allocator) void {
        if (self.default_device) |value| allocator.free(value);
        if (self.smoke_scenario) |value| allocator.free(value);
        if (self.trace_dir) |value| allocator.free(value);
        if (self.avd_name) |value| allocator.free(value);
        if (self.restore_snapshot) |value| allocator.free(value);
        if (self.avd_system_image) |value| allocator.free(value);
        if (self.avd_device_profile) |value| allocator.free(value);
    }
};

pub const ToolsConfig = struct {
    adb_path: ?[]const u8 = null,
    emulator_path: ?[]const u8 = null,
    avdmanager_path: ?[]const u8 = null,
    android_shim_path: ?[]const u8 = null,
    xcrun_path: ?[]const u8 = null,
    ios_shim_path: ?[]const u8 = null,
    zig_path: ?[]const u8 = null,

    pub fn deinit(self: *ToolsConfig, allocator: std.mem.Allocator) void {
        if (self.adb_path) |value| allocator.free(value);
        if (self.emulator_path) |value| allocator.free(value);
        if (self.avdmanager_path) |value| allocator.free(value);
        if (self.android_shim_path) |value| allocator.free(value);
        if (self.xcrun_path) |value| allocator.free(value);
        if (self.ios_shim_path) |value| allocator.free(value);
        if (self.zig_path) |value| allocator.free(value);
    }
};

pub const ArtifactConfig = struct {
    screenshots: bool = true,
    hierarchy: bool = true,
    logs: bool = true,
    screen_recording: bool = false,
};

pub const RedactionConfig = struct {
    denylist_text: []const []const u8 = &.{},
    allowlist_text: []const []const u8 = &.{},
    denylist_resource_ids: []const []const u8 = &.{},
    allowlist_resource_ids: []const []const u8 = &.{},

    pub fn deinit(self: *RedactionConfig, allocator: std.mem.Allocator) void {
        freeStringList(allocator, self.denylist_text);
        freeStringList(allocator, self.allowlist_text);
        freeStringList(allocator, self.denylist_resource_ids);
        freeStringList(allocator, self.allowlist_resource_ids);
    }
};

pub const Config = struct {
    schema_version: u32,
    app_id: ?[]const u8 = null,
    android: PlatformConfig = .{},
    ios: PlatformConfig = .{},
    tools: ToolsConfig = .{},
    artifacts: ArtifactConfig = .{},
    redaction: RedactionConfig = .{},

    pub fn deinit(self: *Config, allocator: std.mem.Allocator) void {
        if (self.app_id) |value| allocator.free(value);
        self.android.deinit(allocator);
        self.ios.deinit(allocator);
        self.tools.deinit(allocator);
        self.redaction.deinit(allocator);
    }
};

pub fn parseFile(allocator: std.mem.Allocator, path: []const u8) !Config {
    const content = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
    defer allocator.free(content);
    return try parseSlice(allocator, content);
}

pub fn errorFieldPathForFile(allocator: std.mem.Allocator, path: []const u8, err: anyerror) !?[]const u8 {
    const content = std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024) catch return null;
    defer allocator.free(content);
    return try errorFieldPathForSlice(allocator, content, err);
}

pub fn parseSlice(allocator: std.mem.Allocator, content: []const u8) !Config {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, content, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.ConfigMustBeObject;
    const object = parsed.value.object;
    try rejectUnknownFields(object, &.{ "schemaVersion", "appId", "android", "ios", "artifacts", "redaction", "tools", "scripts" });
    try validateScripts(object.get("scripts"));
    const schema_version = try requiredU32(object, "schemaVersion");

    var cfg = Config{
        .schema_version = schema_version,
        .app_id = try optionalString(allocator, object, "appId"),
        .android = try platformConfig(allocator, object.get("android")),
        .ios = try platformConfig(allocator, object.get("ios")),
        .tools = try toolsConfig(allocator, object.get("tools")),
        .artifacts = try artifactConfig(object.get("artifacts")),
        .redaction = try redactionConfig(allocator, object.get("redaction")),
    };
    errdefer cfg.deinit(allocator);

    if (cfg.schema_version != 1) return error.UnsupportedConfigVersion;
    return cfg;
}

fn platformConfig(allocator: std.mem.Allocator, maybe_value: ?std.json.Value) !PlatformConfig {
    const value = maybe_value orelse return .{};
    if (value != .object) return error.ConfigPlatformMustBeObject;
    const object = value.object;
    try rejectUnknownFields(object, &.{
        "enabled",
        "defaultDevice",
        "smokeScenario",
        "traceDir",
        "avdName",
        "restoreSnapshot",
        "createAvdIfMissing",
        "avdSystemImage",
        "avdDeviceProfile",
        "resetBeforeRun",
        "waitReady",
    });
    return .{
        .enabled = try optionalBool(object, "enabled") orelse false,
        .default_device = try optionalString(allocator, object, "defaultDevice"),
        .smoke_scenario = try optionalString(allocator, object, "smokeScenario"),
        .trace_dir = try optionalString(allocator, object, "traceDir"),
        .avd_name = try optionalString(allocator, object, "avdName"),
        .restore_snapshot = try optionalString(allocator, object, "restoreSnapshot"),
        .avd_system_image = try optionalString(allocator, object, "avdSystemImage"),
        .avd_device_profile = try optionalString(allocator, object, "avdDeviceProfile"),
        .reset_before_run = try optionalBool(object, "resetBeforeRun") orelse false,
        .wait_ready = try optionalBool(object, "waitReady") orelse false,
        .create_avd_if_missing = try optionalBool(object, "createAvdIfMissing") orelse false,
    };
}

fn errorFieldPathForSlice(allocator: std.mem.Allocator, content: []const u8, err: anyerror) !?[]const u8 {
    if (err == error.ConfigMustBeObject) return try allocator.dupe(u8, "$");
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, content, .{}) catch return null;
    defer parsed.deinit();
    if (parsed.value != .object) return null;
    const object = parsed.value.object;

    return switch (err) {
        error.MissingConfigSchemaVersion,
        error.ConfigSchemaVersionMustBeInteger,
        error.UnsupportedConfigVersion,
        => try allocator.dupe(u8, "$.schemaVersion"),
        error.ConfigUnknownField => try findUnknownFieldPath(allocator, object),
        error.ConfigScriptsMustBeObject => try objectTypeFieldPath(allocator, object, "scripts", "$.scripts"),
        error.ConfigPlatformMustBeObject => try firstObjectTypeFieldPath(allocator, object, &.{ "android", "ios" }),
        error.ConfigToolsMustBeObject => try objectTypeFieldPath(allocator, object, "tools", "$.tools"),
        error.ConfigArtifactsMustBeObject => try objectTypeFieldPath(allocator, object, "artifacts", "$.artifacts"),
        error.ConfigRedactionMustBeObject => try objectTypeFieldPath(allocator, object, "redaction", "$.redaction"),
        error.ConfigFieldMustBeBool => try findBoolFieldPath(allocator, object),
        error.ConfigFieldMustBeString => try findStringFieldPath(allocator, object),
        error.ConfigFieldMustBeNonEmptyString => try findNonEmptyStringFieldPath(allocator, object),
        error.ConfigFieldMustBeStringArray => try findStringArrayFieldPath(allocator, object),
        else => null,
    };
}

fn toolsConfig(allocator: std.mem.Allocator, maybe_value: ?std.json.Value) !ToolsConfig {
    const value = maybe_value orelse return .{};
    if (value != .object) return error.ConfigToolsMustBeObject;
    const object = value.object;
    try rejectUnknownFields(object, &.{ "adbPath", "emulatorPath", "avdmanagerPath", "androidShimPath", "xcrunPath", "iosShimPath", "zigPath" });
    return .{
        .adb_path = try optionalString(allocator, object, "adbPath"),
        .emulator_path = try optionalString(allocator, object, "emulatorPath"),
        .avdmanager_path = try optionalString(allocator, object, "avdmanagerPath"),
        .android_shim_path = try optionalString(allocator, object, "androidShimPath"),
        .xcrun_path = try optionalString(allocator, object, "xcrunPath"),
        .ios_shim_path = try optionalString(allocator, object, "iosShimPath"),
        .zig_path = try optionalString(allocator, object, "zigPath"),
    };
}

fn artifactConfig(maybe_value: ?std.json.Value) !ArtifactConfig {
    const value = maybe_value orelse return .{};
    if (value != .object) return error.ConfigArtifactsMustBeObject;
    const object = value.object;
    try rejectUnknownFields(object, &.{ "screenshots", "hierarchy", "logs", "screenRecording" });
    return .{
        .screenshots = try optionalBool(object, "screenshots") orelse true,
        .hierarchy = try optionalBool(object, "hierarchy") orelse true,
        .logs = try optionalBool(object, "logs") orelse true,
        .screen_recording = try optionalBool(object, "screenRecording") orelse false,
    };
}

fn redactionConfig(allocator: std.mem.Allocator, maybe_value: ?std.json.Value) !RedactionConfig {
    const value = maybe_value orelse return .{};
    if (value != .object) return error.ConfigRedactionMustBeObject;
    const object = value.object;
    try rejectUnknownFields(object, &.{ "denylistText", "allowlistText", "denylistResourceIds", "allowlistResourceIds" });
    var parsed = RedactionConfig{};
    errdefer parsed.deinit(allocator);
    parsed.denylist_text = try optionalStringList(allocator, object, "denylistText");
    parsed.allowlist_text = try optionalStringList(allocator, object, "allowlistText");
    parsed.denylist_resource_ids = try optionalStringList(allocator, object, "denylistResourceIds");
    parsed.allowlist_resource_ids = try optionalStringList(allocator, object, "allowlistResourceIds");
    return parsed;
}

fn rejectUnknownFields(object: std.json.ObjectMap, allowed: []const []const u8) !void {
    var iterator = object.iterator();
    while (iterator.next()) |entry| {
        var found = false;
        for (allowed) |key| {
            if (std.mem.eql(u8, entry.key_ptr.*, key)) {
                found = true;
                break;
            }
        }
        if (!found) return error.ConfigUnknownField;
    }
}

fn findUnknownFieldPath(allocator: std.mem.Allocator, object: std.json.ObjectMap) !?[]const u8 {
    const root_allowed = [_][]const u8{ "schemaVersion", "appId", "android", "ios", "artifacts", "redaction", "tools", "scripts" };
    if (try unknownInObject(allocator, object, "$", root_allowed[0..])) |path| return path;

    const platform_allowed = [_][]const u8{
        "enabled",
        "defaultDevice",
        "smokeScenario",
        "traceDir",
        "avdName",
        "restoreSnapshot",
        "createAvdIfMissing",
        "avdSystemImage",
        "avdDeviceProfile",
        "resetBeforeRun",
        "waitReady",
    };
    if (try unknownInNestedObject(allocator, object, "android", "$.android", platform_allowed[0..])) |path| return path;
    if (try unknownInNestedObject(allocator, object, "ios", "$.ios", platform_allowed[0..])) |path| return path;

    const tools_allowed = [_][]const u8{ "adbPath", "emulatorPath", "avdmanagerPath", "androidShimPath", "xcrunPath", "iosShimPath", "zigPath" };
    if (try unknownInNestedObject(allocator, object, "tools", "$.tools", tools_allowed[0..])) |path| return path;

    const artifact_allowed = [_][]const u8{ "screenshots", "hierarchy", "logs", "screenRecording" };
    if (try unknownInNestedObject(allocator, object, "artifacts", "$.artifacts", artifact_allowed[0..])) |path| return path;

    const redaction_allowed = [_][]const u8{ "denylistText", "allowlistText", "denylistResourceIds", "allowlistResourceIds" };
    if (try unknownInNestedObject(allocator, object, "redaction", "$.redaction", redaction_allowed[0..])) |path| return path;

    return null;
}

fn unknownInNestedObject(allocator: std.mem.Allocator, object: std.json.ObjectMap, key: []const u8, prefix: []const u8, allowed: []const []const u8) !?[]const u8 {
    const value = object.get(key) orelse return null;
    if (value != .object) return null;
    return try unknownInObject(allocator, value.object, prefix, allowed);
}

fn unknownInObject(allocator: std.mem.Allocator, object: std.json.ObjectMap, prefix: []const u8, allowed: []const []const u8) !?[]const u8 {
    var iterator = object.iterator();
    while (iterator.next()) |entry| {
        if (!containsString(allowed, entry.key_ptr.*)) {
            return try std.fmt.allocPrint(allocator, "{s}.{s}", .{ prefix, entry.key_ptr.* });
        }
    }
    return null;
}

fn containsString(values: []const []const u8, needle: []const u8) bool {
    for (values) |value| {
        if (std.mem.eql(u8, value, needle)) return true;
    }
    return false;
}

fn objectTypeFieldPath(allocator: std.mem.Allocator, object: std.json.ObjectMap, key: []const u8, path: []const u8) !?[]const u8 {
    const value = object.get(key) orelse return null;
    if (value != .object) return try allocator.dupe(u8, path);
    return null;
}

fn firstObjectTypeFieldPath(allocator: std.mem.Allocator, object: std.json.ObjectMap, keys: []const []const u8) !?[]const u8 {
    for (keys) |key| {
        const value = object.get(key) orelse continue;
        if (value != .object) return try std.fmt.allocPrint(allocator, "$.{s}", .{key});
    }
    return null;
}

fn findBoolFieldPath(allocator: std.mem.Allocator, object: std.json.ObjectMap) !?[]const u8 {
    const platform_bool_keys = [_][]const u8{ "enabled", "resetBeforeRun", "waitReady", "createAvdIfMissing" };
    if (try fieldWithUnexpectedTag(allocator, object, "android", "$.android", platform_bool_keys[0..], .bool)) |path| return path;
    if (try fieldWithUnexpectedTag(allocator, object, "ios", "$.ios", platform_bool_keys[0..], .bool)) |path| return path;

    const artifact_bool_keys = [_][]const u8{ "screenshots", "hierarchy", "logs", "screenRecording" };
    if (try fieldWithUnexpectedTag(allocator, object, "artifacts", "$.artifacts", artifact_bool_keys[0..], .bool)) |path| return path;
    return null;
}

fn findStringFieldPath(allocator: std.mem.Allocator, object: std.json.ObjectMap) !?[]const u8 {
    if (try scriptValueWithUnexpectedTag(allocator, object, .string, false)) |path| return path;
    if (try directFieldWithUnexpectedTag(allocator, object, "appId", "$.appId", .string, false)) |path| return path;
    const platform_string_keys = [_][]const u8{ "defaultDevice", "smokeScenario", "traceDir", "avdName", "restoreSnapshot", "avdSystemImage", "avdDeviceProfile" };
    if (try fieldWithUnexpectedTag(allocator, object, "android", "$.android", platform_string_keys[0..], .string)) |path| return path;
    if (try fieldWithUnexpectedTag(allocator, object, "ios", "$.ios", platform_string_keys[0..], .string)) |path| return path;
    const tools_string_keys = [_][]const u8{ "adbPath", "emulatorPath", "avdmanagerPath", "androidShimPath", "xcrunPath", "iosShimPath", "zigPath" };
    if (try fieldWithUnexpectedTag(allocator, object, "tools", "$.tools", tools_string_keys[0..], .string)) |path| return path;
    return null;
}

fn findNonEmptyStringFieldPath(allocator: std.mem.Allocator, object: std.json.ObjectMap) !?[]const u8 {
    if (try scriptValueWithUnexpectedTag(allocator, object, .string, true)) |path| return path;
    if (try emptyDirectStringFieldPath(allocator, object, "appId", "$.appId")) |path| return path;
    const platform_string_keys = [_][]const u8{ "defaultDevice", "smokeScenario", "traceDir", "avdName", "restoreSnapshot", "avdSystemImage", "avdDeviceProfile" };
    if (try emptyNestedStringFieldPath(allocator, object, "android", "$.android", platform_string_keys[0..])) |path| return path;
    if (try emptyNestedStringFieldPath(allocator, object, "ios", "$.ios", platform_string_keys[0..])) |path| return path;
    const tools_string_keys = [_][]const u8{ "adbPath", "emulatorPath", "avdmanagerPath", "androidShimPath", "xcrunPath", "iosShimPath", "zigPath" };
    if (try emptyNestedStringFieldPath(allocator, object, "tools", "$.tools", tools_string_keys[0..])) |path| return path;
    const redaction_keys = [_][]const u8{ "denylistText", "allowlistText", "denylistResourceIds", "allowlistResourceIds" };
    if (try emptyStringArrayItemPath(allocator, object, "redaction", "$.redaction", redaction_keys[0..])) |path| return path;
    return null;
}

fn findStringArrayFieldPath(allocator: std.mem.Allocator, object: std.json.ObjectMap) !?[]const u8 {
    const redaction_keys = [_][]const u8{ "denylistText", "allowlistText", "denylistResourceIds", "allowlistResourceIds" };
    const redaction = object.get("redaction") orelse return null;
    if (redaction != .object) return null;
    for (redaction_keys) |key| {
        const value = redaction.object.get(key) orelse continue;
        if (value != .array) return try std.fmt.allocPrint(allocator, "$.redaction.{s}", .{key});
        for (value.array.items, 0..) |item, index| {
            if (item != .string) return try std.fmt.allocPrint(allocator, "$.redaction.{s}[{d}]", .{ key, index });
        }
    }
    return null;
}

fn fieldWithUnexpectedTag(allocator: std.mem.Allocator, object: std.json.ObjectMap, parent_key: []const u8, prefix: []const u8, keys: []const []const u8, expected: std.meta.Tag(std.json.Value)) !?[]const u8 {
    const parent = object.get(parent_key) orelse return null;
    if (parent != .object) return null;
    for (keys) |key| {
        if (try directFieldWithUnexpectedTag(allocator, parent.object, key, try std.fmt.allocPrint(allocator, "{s}.{s}", .{ prefix, key }), expected, true)) |path| return path;
    }
    return null;
}

fn directFieldWithUnexpectedTag(allocator: std.mem.Allocator, object: std.json.ObjectMap, key: []const u8, path: []const u8, expected: std.meta.Tag(std.json.Value), free_path: bool) !?[]const u8 {
    defer if (free_path) allocator.free(path);
    const value = object.get(key) orelse return null;
    if (value == .null and expected == .string) return null;
    if (std.meta.activeTag(value) != expected) return try allocator.dupe(u8, path);
    return null;
}

fn scriptValueWithUnexpectedTag(allocator: std.mem.Allocator, object: std.json.ObjectMap, expected: std.meta.Tag(std.json.Value), reject_empty: bool) !?[]const u8 {
    const scripts = object.get("scripts") orelse return null;
    if (scripts != .object) return null;
    var iterator = scripts.object.iterator();
    while (iterator.next()) |entry| {
        const path = try std.fmt.allocPrint(allocator, "$.scripts.{s}", .{entry.key_ptr.*});
        errdefer allocator.free(path);
        if (std.meta.activeTag(entry.value_ptr.*) != expected) return path;
        if (reject_empty and entry.value_ptr.string.len == 0) return path;
        allocator.free(path);
    }
    return null;
}

fn emptyDirectStringFieldPath(allocator: std.mem.Allocator, object: std.json.ObjectMap, key: []const u8, path: []const u8) !?[]const u8 {
    const value = object.get(key) orelse return null;
    if (value == .string and value.string.len == 0) return try allocator.dupe(u8, path);
    return null;
}

fn emptyNestedStringFieldPath(allocator: std.mem.Allocator, object: std.json.ObjectMap, parent_key: []const u8, prefix: []const u8, keys: []const []const u8) !?[]const u8 {
    const parent = object.get(parent_key) orelse return null;
    if (parent != .object) return null;
    for (keys) |key| {
        const value = parent.object.get(key) orelse continue;
        const path = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ prefix, key });
        defer allocator.free(path);
        if (value == .string and value.string.len == 0) return try allocator.dupe(u8, path);
    }
    return null;
}

fn emptyStringArrayItemPath(allocator: std.mem.Allocator, object: std.json.ObjectMap, parent_key: []const u8, prefix: []const u8, keys: []const []const u8) !?[]const u8 {
    const parent = object.get(parent_key) orelse return null;
    if (parent != .object) return null;
    for (keys) |key| {
        const value = parent.object.get(key) orelse continue;
        if (value != .array) continue;
        for (value.array.items, 0..) |item, index| {
            if (item == .string and item.string.len == 0) return try std.fmt.allocPrint(allocator, "{s}.{s}[{d}]", .{ prefix, key, index });
        }
    }
    return null;
}

fn validateScripts(maybe_value: ?std.json.Value) !void {
    const value = maybe_value orelse return;
    if (value != .object) return error.ConfigScriptsMustBeObject;
    var iterator = value.object.iterator();
    while (iterator.next()) |entry| {
        if (entry.value_ptr.* != .string) return error.ConfigFieldMustBeString;
        if (entry.value_ptr.string.len == 0) return error.ConfigFieldMustBeNonEmptyString;
    }
}

fn requiredU32(object: std.json.ObjectMap, key: []const u8) !u32 {
    const value = object.get(key) orelse return error.MissingConfigSchemaVersion;
    if (value != .integer) return error.ConfigSchemaVersionMustBeInteger;
    if (value.integer < 0 or value.integer > std.math.maxInt(u32)) return error.ConfigSchemaVersionMustBeInteger;
    return @intCast(value.integer);
}

fn optionalString(allocator: std.mem.Allocator, object: std.json.ObjectMap, key: []const u8) !?[]const u8 {
    const value = object.get(key) orelse return null;
    if (value == .null) return null;
    if (value != .string) return error.ConfigFieldMustBeString;
    if (value.string.len == 0) return error.ConfigFieldMustBeNonEmptyString;
    return try allocator.dupe(u8, value.string);
}

fn optionalBool(object: std.json.ObjectMap, key: []const u8) !?bool {
    const value = object.get(key) orelse return null;
    if (value != .bool) return error.ConfigFieldMustBeBool;
    return value.bool;
}

fn optionalStringList(allocator: std.mem.Allocator, object: std.json.ObjectMap, key: []const u8) ![]const []const u8 {
    const value = object.get(key) orelse return &.{};
    if (value != .array) return error.ConfigFieldMustBeStringArray;
    if (value.array.items.len == 0) return &.{};

    var output = try allocator.alloc([]const u8, value.array.items.len);
    errdefer allocator.free(output);
    var written: usize = 0;
    errdefer {
        for (output[0..written]) |item| allocator.free(item);
    }

    for (value.array.items, 0..) |item, index| {
        if (item != .string) return error.ConfigFieldMustBeStringArray;
        if (item.string.len == 0) return error.ConfigFieldMustBeNonEmptyString;
        output[index] = try allocator.dupe(u8, item.string);
        written += 1;
    }
    return output;
}

fn freeStringList(allocator: std.mem.Allocator, list: []const []const u8) void {
    if (list.len == 0) return;
    for (list) |item| allocator.free(item);
    allocator.free(list);
}

test "config parser reads app-local defaults" {
    var cfg = try parseSlice(std.testing.allocator,
        \\{
        \\  "schemaVersion": 1,
        \\  "appId": "com.example.mobiletest",
        \\  "android": {
        \\    "enabled": true,
        \\    "defaultDevice": "emulator-5554",
        \\    "smokeScenario": ".zmr/android-smoke.json",
        \\    "traceDir": "traces/android",
        \\    "avdName": "Small_Phone",
        \\    "restoreSnapshot": "zmr-clean",
        \\    "resetBeforeRun": true,
        \\    "waitReady": true,
        \\    "createAvdIfMissing": true,
        \\    "avdSystemImage": "system-images;android-35;google_apis;arm64-v8a",
        \\    "avdDeviceProfile": "pixel_6"
        \\  },
        \\  "tools": {
        \\    "adbPath": "./fake-adb",
        \\    "avdmanagerPath": "./fake-avdmanager",
        \\    "androidShimPath": "./fake-android-shim",
        \\    "iosShimPath": "./fake-ios-shim"
        \\  }
        \\}
    );
    defer cfg.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u32, 1), cfg.schema_version);
    try std.testing.expectEqualStrings("com.example.mobiletest", cfg.app_id.?);
    try std.testing.expect(cfg.android.enabled);
    try std.testing.expectEqualStrings("emulator-5554", cfg.android.default_device.?);
    try std.testing.expectEqualStrings(".zmr/android-smoke.json", cfg.android.smoke_scenario.?);
    try std.testing.expectEqualStrings("traces/android", cfg.android.trace_dir.?);
    try std.testing.expectEqualStrings("Small_Phone", cfg.android.avd_name.?);
    try std.testing.expectEqualStrings("zmr-clean", cfg.android.restore_snapshot.?);
    try std.testing.expect(cfg.android.reset_before_run);
    try std.testing.expect(cfg.android.wait_ready);
    try std.testing.expect(cfg.android.create_avd_if_missing);
    try std.testing.expectEqualStrings("system-images;android-35;google_apis;arm64-v8a", cfg.android.avd_system_image.?);
    try std.testing.expectEqualStrings("pixel_6", cfg.android.avd_device_profile.?);
    try std.testing.expectEqualStrings("./fake-adb", cfg.tools.adb_path.?);
    try std.testing.expectEqualStrings("./fake-avdmanager", cfg.tools.avdmanager_path.?);
    try std.testing.expectEqualStrings("./fake-android-shim", cfg.tools.android_shim_path.?);
    try std.testing.expectEqualStrings("./fake-ios-shim", cfg.tools.ios_shim_path.?);
}

test "config parser rejects unsupported versions" {
    try std.testing.expectError(error.UnsupportedConfigVersion, parseSlice(std.testing.allocator,
        \\{"schemaVersion": 2}
    ));
}

test "config parser rejects non-boolean platform flags" {
    try std.testing.expectError(error.ConfigFieldMustBeBool, parseSlice(std.testing.allocator,
        \\{
        \\  "schemaVersion": 1,
        \\  "android": {
        \\    "enabled": "true"
        \\  }
        \\}
    ));
}

test "config parser rejects unknown fields" {
    try std.testing.expectError(error.ConfigUnknownField, parseSlice(std.testing.allocator,
        \\{
        \\  "schemaVersion": 1,
        \\  "android": {
        \\    "smokeScenaro": ".zmr/android-smoke.json"
        \\  }
        \\}
    ));
}

test "config parser rejects empty strings where schema requires values" {
    try std.testing.expectError(error.ConfigFieldMustBeNonEmptyString, parseSlice(std.testing.allocator,
        \\{
        \\  "schemaVersion": 1,
        \\  "appId": ""
        \\}
    ));

    try std.testing.expectError(error.ConfigFieldMustBeNonEmptyString, parseSlice(std.testing.allocator,
        \\{
        \\  "schemaVersion": 1,
        \\  "tools": {
        \\    "adbPath": ""
        \\  }
        \\}
    ));

    try std.testing.expectError(error.ConfigFieldMustBeNonEmptyString, parseSlice(std.testing.allocator,
        \\{
        \\  "schemaVersion": 1,
        \\  "redaction": {
        \\    "denylistText": [""]
        \\  }
        \\}
    ));
}

test "config error diagnostics identify actionable field paths" {
    const allocator = std.testing.allocator;

    const root = try errorFieldPathForSlice(allocator,
        \\[]
    , error.ConfigMustBeObject);
    defer allocator.free(root.?);
    try std.testing.expectEqualStrings("$", root.?);

    const schema_version = try errorFieldPathForSlice(allocator,
        \\{
        \\  "schemaVersion": "1"
        \\}
    , error.ConfigSchemaVersionMustBeInteger);
    defer allocator.free(schema_version.?);
    try std.testing.expectEqualStrings("$.schemaVersion", schema_version.?);

    const scripts_object = try errorFieldPathForSlice(allocator,
        \\{
        \\  "schemaVersion": 1,
        \\  "scripts": []
        \\}
    , error.ConfigScriptsMustBeObject);
    defer allocator.free(scripts_object.?);
    try std.testing.expectEqualStrings("$.scripts", scripts_object.?);

    const platform_object = try errorFieldPathForSlice(allocator,
        \\{
        \\  "schemaVersion": 1,
        \\  "android": false
        \\}
    , error.ConfigPlatformMustBeObject);
    defer allocator.free(platform_object.?);
    try std.testing.expectEqualStrings("$.android", platform_object.?);

    const tools_object = try errorFieldPathForSlice(allocator,
        \\{
        \\  "schemaVersion": 1,
        \\  "tools": false
        \\}
    , error.ConfigToolsMustBeObject);
    defer allocator.free(tools_object.?);
    try std.testing.expectEqualStrings("$.tools", tools_object.?);

    const artifacts_object = try errorFieldPathForSlice(allocator,
        \\{
        \\  "schemaVersion": 1,
        \\  "artifacts": false
        \\}
    , error.ConfigArtifactsMustBeObject);
    defer allocator.free(artifacts_object.?);
    try std.testing.expectEqualStrings("$.artifacts", artifacts_object.?);

    const redaction_object = try errorFieldPathForSlice(allocator,
        \\{
        \\  "schemaVersion": 1,
        \\  "redaction": false
        \\}
    , error.ConfigRedactionMustBeObject);
    defer allocator.free(redaction_object.?);
    try std.testing.expectEqualStrings("$.redaction", redaction_object.?);

    const unknown = try errorFieldPathForSlice(allocator,
        \\{
        \\  "schemaVersion": 1,
        \\  "android": {
        \\    "smokeScenaro": ".zmr/android-smoke.json"
        \\  }
        \\}
    , error.ConfigUnknownField);
    defer allocator.free(unknown.?);
    try std.testing.expectEqualStrings("$.android.smokeScenaro", unknown.?);

    const ios_unknown = try errorFieldPathForSlice(allocator,
        \\{
        \\  "schemaVersion": 1,
        \\  "ios": {
        \\    "smokeScenaro": ".zmr/ios-smoke.json"
        \\  }
        \\}
    , error.ConfigUnknownField);
    defer allocator.free(ios_unknown.?);
    try std.testing.expectEqualStrings("$.ios.smokeScenaro", ios_unknown.?);

    const tools_unknown = try errorFieldPathForSlice(allocator,
        \\{
        \\  "schemaVersion": 1,
        \\  "tools": {
        \\    "adb": "./adb"
        \\  }
        \\}
    , error.ConfigUnknownField);
    defer allocator.free(tools_unknown.?);
    try std.testing.expectEqualStrings("$.tools.adb", tools_unknown.?);

    const artifacts_unknown = try errorFieldPathForSlice(allocator,
        \\{
        \\  "schemaVersion": 1,
        \\  "artifacts": {
        \\    "video": true
        \\  }
        \\}
    , error.ConfigUnknownField);
    defer allocator.free(artifacts_unknown.?);
    try std.testing.expectEqualStrings("$.artifacts.video", artifacts_unknown.?);

    const redaction_unknown = try errorFieldPathForSlice(allocator,
        \\{
        \\  "schemaVersion": 1,
        \\  "redaction": {
        \\    "denyText": ["secret"]
        \\  }
        \\}
    , error.ConfigUnknownField);
    defer allocator.free(redaction_unknown.?);
    try std.testing.expectEqualStrings("$.redaction.denyText", redaction_unknown.?);

    const no_unknown = try errorFieldPathForSlice(allocator,
        \\{
        \\  "schemaVersion": 1
        \\}
    , error.ConfigUnknownField);
    try std.testing.expect(no_unknown == null);

    const bool_path = try errorFieldPathForSlice(allocator,
        \\{
        \\  "schemaVersion": 1,
        \\  "artifacts": {
        \\    "screenshots": "false"
        \\  }
        \\}
    , error.ConfigFieldMustBeBool);
    defer allocator.free(bool_path.?);
    try std.testing.expectEqualStrings("$.artifacts.screenshots", bool_path.?);

    const script_type = try errorFieldPathForSlice(allocator,
        \\{
        \\  "schemaVersion": 1,
        \\  "scripts": {
        \\    "android": false
        \\  }
        \\}
    , error.ConfigFieldMustBeString);
    defer allocator.free(script_type.?);
    try std.testing.expectEqualStrings("$.scripts.android", script_type.?);

    const app_id_type = try errorFieldPathForSlice(allocator,
        \\{
        \\  "schemaVersion": 1,
        \\  "appId": false
        \\}
    , error.ConfigFieldMustBeString);
    defer allocator.free(app_id_type.?);
    try std.testing.expectEqualStrings("$.appId", app_id_type.?);

    const android_string_type = try errorFieldPathForSlice(allocator,
        \\{
        \\  "schemaVersion": 1,
        \\  "android": {
        \\    "defaultDevice": false
        \\  }
        \\}
    , error.ConfigFieldMustBeString);
    defer allocator.free(android_string_type.?);
    try std.testing.expectEqualStrings("$.android.defaultDevice", android_string_type.?);

    const ios_string_type = try errorFieldPathForSlice(allocator,
        \\{
        \\  "schemaVersion": 1,
        \\  "ios": {
        \\    "smokeScenario": false
        \\  }
        \\}
    , error.ConfigFieldMustBeString);
    defer allocator.free(ios_string_type.?);
    try std.testing.expectEqualStrings("$.ios.smokeScenario", ios_string_type.?);

    const tools_string_type = try errorFieldPathForSlice(allocator,
        \\{
        \\  "schemaVersion": 1,
        \\  "tools": {
        \\    "adbPath": false
        \\  }
        \\}
    , error.ConfigFieldMustBeString);
    defer allocator.free(tools_string_type.?);
    try std.testing.expectEqualStrings("$.tools.adbPath", tools_string_type.?);

    const no_string_type = try errorFieldPathForSlice(allocator,
        \\{
        \\  "schemaVersion": 1,
        \\  "scripts": {
        \\    "android": "zmr run .zmr/android-smoke.json"
        \\  }
        \\}
    , error.ConfigFieldMustBeString);
    try std.testing.expect(no_string_type == null);

    const empty_app_id = try errorFieldPathForSlice(allocator,
        \\{
        \\  "schemaVersion": 1,
        \\  "appId": ""
        \\}
    , error.ConfigFieldMustBeNonEmptyString);
    defer allocator.free(empty_app_id.?);
    try std.testing.expectEqualStrings("$.appId", empty_app_id.?);

    const empty_tool = try errorFieldPathForSlice(allocator,
        \\{
        \\  "schemaVersion": 1,
        \\  "tools": {
        \\    "adbPath": ""
        \\  }
        \\}
    , error.ConfigFieldMustBeNonEmptyString);
    defer allocator.free(empty_tool.?);
    try std.testing.expectEqualStrings("$.tools.adbPath", empty_tool.?);

    const empty_script = try errorFieldPathForSlice(allocator,
        \\{
        \\  "schemaVersion": 1,
        \\  "scripts": {
        \\    "android": ""
        \\  }
        \\}
    , error.ConfigFieldMustBeNonEmptyString);
    defer allocator.free(empty_script.?);
    try std.testing.expectEqualStrings("$.scripts.android", empty_script.?);

    const empty_redaction = try errorFieldPathForSlice(allocator,
        \\{
        \\  "schemaVersion": 1,
        \\  "redaction": {
        \\    "denylistText": [""]
        \\  }
        \\}
    , error.ConfigFieldMustBeNonEmptyString);
    defer allocator.free(empty_redaction.?);
    try std.testing.expectEqualStrings("$.redaction.denylistText[0]", empty_redaction.?);

    const redaction_not_array = try errorFieldPathForSlice(allocator,
        \\{
        \\  "schemaVersion": 1,
        \\  "redaction": {
        \\    "denylistText": false
        \\  }
        \\}
    , error.ConfigFieldMustBeStringArray);
    defer allocator.free(redaction_not_array.?);
    try std.testing.expectEqualStrings("$.redaction.denylistText", redaction_not_array.?);

    const bad_redaction = try errorFieldPathForSlice(allocator,
        \\{
        \\  "schemaVersion": 1,
        \\  "redaction": {
        \\    "denylistText": ["ok", false]
        \\  }
        \\}
    , error.ConfigFieldMustBeStringArray);
    defer allocator.free(bad_redaction.?);
    try std.testing.expectEqualStrings("$.redaction.denylistText[1]", bad_redaction.?);
}

test "config parser validates optional scripts block" {
    var cfg = try parseSlice(std.testing.allocator,
        \\{
        \\  "schemaVersion": 1,
        \\  "scripts": {
        \\    "android": "zmr run .zmr/android-smoke.json"
        \\  }
        \\}
    );
    defer cfg.deinit(std.testing.allocator);

    try std.testing.expectError(error.ConfigFieldMustBeString, parseSlice(std.testing.allocator,
        \\{
        \\  "schemaVersion": 1,
        \\  "scripts": {
        \\    "android": false
        \\  }
        \\}
    ));

    try std.testing.expectError(error.ConfigFieldMustBeNonEmptyString, parseSlice(std.testing.allocator,
        \\{
        \\  "schemaVersion": 1,
        \\  "scripts": {
        \\    "android": ""
        \\  }
        \\}
    ));
}

test "config parser reads artifact capture controls" {
    const allocator = std.testing.allocator;
    var cfg = try parseSlice(allocator,
        \\{
        \\  "schemaVersion": 1,
        \\  "artifacts": {
        \\    "screenshots": false,
        \\    "hierarchy": false,
        \\    "logs": false,
        \\    "screenRecording": true
        \\  }
        \\}
    );
    defer cfg.deinit(allocator);

    try std.testing.expect(!cfg.artifacts.screenshots);
    try std.testing.expect(!cfg.artifacts.hierarchy);
    try std.testing.expect(!cfg.artifacts.logs);
    try std.testing.expect(cfg.artifacts.screen_recording);
}

test "config parser rejects non-boolean artifact controls" {
    try std.testing.expectError(error.ConfigFieldMustBeBool, parseSlice(std.testing.allocator,
        \\{
        \\  "schemaVersion": 1,
        \\  "artifacts": {
        \\    "screenshots": "false"
        \\  }
        \\}
    ));
}

test "config parser reads trace redaction controls" {
    const allocator = std.testing.allocator;
    var cfg = try parseSlice(allocator,
        \\{
        \\  "schemaVersion": 1,
        \\  "redaction": {
        \\    "denylistText": ["customer dob", "internal token"],
        \\    "allowlistText": ["public token label"],
        \\    "denylistResourceIds": ["password-field", "ssn"],
        \\    "allowlistResourceIds": ["public-token-label"]
        \\  }
        \\}
    );
    defer cfg.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), cfg.redaction.denylist_text.len);
    try std.testing.expectEqualStrings("customer dob", cfg.redaction.denylist_text[0]);
    try std.testing.expectEqualStrings("internal token", cfg.redaction.denylist_text[1]);
    try std.testing.expectEqual(@as(usize, 1), cfg.redaction.allowlist_text.len);
    try std.testing.expectEqualStrings("public token label", cfg.redaction.allowlist_text[0]);
    try std.testing.expectEqual(@as(usize, 2), cfg.redaction.denylist_resource_ids.len);
    try std.testing.expectEqualStrings("password-field", cfg.redaction.denylist_resource_ids[0]);
    try std.testing.expectEqualStrings("ssn", cfg.redaction.denylist_resource_ids[1]);
    try std.testing.expectEqual(@as(usize, 1), cfg.redaction.allowlist_resource_ids.len);
    try std.testing.expectEqualStrings("public-token-label", cfg.redaction.allowlist_resource_ids[0]);
}
