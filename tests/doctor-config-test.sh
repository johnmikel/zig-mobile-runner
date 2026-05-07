#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

ZMR="$ROOT/zig-out/bin/zmr"
test -x "$ZMR"

BAD_CONFIG="$TMPDIR/bad-config.json"
printf '{\n  "schemaVersion": "nope"\n}\n' > "$BAD_CONFIG"

OUTPUT="$("$ZMR" doctor --json --config "$BAD_CONFIG" --adb "$ROOT/tests/fake-adb.sh" --xcrun "$ROOT/tests/fake-xcrun.sh")"

grep -q '"ok":false' <<< "$OUTPUT"
grep -q '"name":"config"' <<< "$OUTPUT"
grep -q '"status":"warning"' <<< "$OUTPUT"
grep -q '"errorCode":"config.schema_version_type"' <<< "$OUTPUT"
grep -q 'ConfigSchemaVersionMustBeInteger' <<< "$OUTPUT"
grep -q '"hint":"Fix the config file or regenerate it with npx zmr-wizard' <<< "$OUTPUT"

BAD_BOOL_CONFIG="$TMPDIR/bad-bool-config.json"
printf '{\n  "schemaVersion": 1,\n  "artifacts": { "screenshots": "false" }\n}\n' > "$BAD_BOOL_CONFIG"

BOOL_OUTPUT="$("$ZMR" doctor --json --config "$BAD_BOOL_CONFIG" --adb "$ROOT/tests/fake-adb.sh" --xcrun "$ROOT/tests/fake-xcrun.sh")"

grep -q '"ok":false' <<< "$BOOL_OUTPUT"
grep -q '"name":"config"' <<< "$BOOL_OUTPUT"
grep -q '"errorCode":"config.field_type"' <<< "$BOOL_OUTPUT"
grep -q 'ConfigFieldMustBeBool' <<< "$BOOL_OUTPUT"

UNKNOWN_FIELD_CONFIG="$TMPDIR/unknown-field-config.json"
printf '{\n  "schemaVersion": 1,\n  "android": { "smokeScenaro": ".zmr/android-smoke.json" }\n}\n' > "$UNKNOWN_FIELD_CONFIG"

UNKNOWN_OUTPUT="$("$ZMR" doctor --json --config "$UNKNOWN_FIELD_CONFIG" --adb "$ROOT/tests/fake-adb.sh" --xcrun "$ROOT/tests/fake-xcrun.sh")"

grep -q '"ok":false' <<< "$UNKNOWN_OUTPUT"
grep -q '"name":"config"' <<< "$UNKNOWN_OUTPUT"
grep -q '"errorCode":"config.unknown_field"' <<< "$UNKNOWN_OUTPUT"
grep -q 'ConfigUnknownField' <<< "$UNKNOWN_OUTPUT"

EMPTY_STRING_CONFIG="$TMPDIR/empty-string-config.json"
printf '{\n  "schemaVersion": 1,\n  "tools": { "adbPath": "" }\n}\n' > "$EMPTY_STRING_CONFIG"

EMPTY_OUTPUT="$("$ZMR" doctor --json --config "$EMPTY_STRING_CONFIG" --adb "$ROOT/tests/fake-adb.sh" --xcrun "$ROOT/tests/fake-xcrun.sh")"

grep -q '"ok":false' <<< "$EMPTY_OUTPUT"
grep -q '"name":"config"' <<< "$EMPTY_OUTPUT"
grep -q '"errorCode":"config.empty_string"' <<< "$EMPTY_OUTPUT"
grep -q '"fieldPath":"$.tools.adbPath"' <<< "$EMPTY_OUTPUT"
grep -q 'ConfigFieldMustBeNonEmptyString' <<< "$EMPTY_OUTPUT"

EMPTY_SCRIPT_CONFIG="$TMPDIR/empty-script-config.json"
printf '{\n  "schemaVersion": 1,\n  "scripts": { "android": "" }\n}\n' > "$EMPTY_SCRIPT_CONFIG"

EMPTY_SCRIPT_OUTPUT="$("$ZMR" doctor --json --config "$EMPTY_SCRIPT_CONFIG" --adb "$ROOT/tests/fake-adb.sh" --xcrun "$ROOT/tests/fake-xcrun.sh")"

grep -q '"ok":false' <<< "$EMPTY_SCRIPT_OUTPUT"
grep -q '"name":"config"' <<< "$EMPTY_SCRIPT_OUTPUT"
grep -q '"errorCode":"config.empty_string"' <<< "$EMPTY_SCRIPT_OUTPUT"
grep -q '"fieldPath":"$.scripts.android"' <<< "$EMPTY_SCRIPT_OUTPUT"
grep -q 'ConfigFieldMustBeNonEmptyString' <<< "$EMPTY_SCRIPT_OUTPUT"

APP_ROOT="$TMPDIR/app"
mkdir -p "$APP_ROOT/.zmr"
printf '#!/usr/bin/env bash\nprintf "{}\\n"\n' > "$APP_ROOT/.zmr/android-shim"
printf '#!/usr/bin/env bash\nprintf "{}\\n"\n' > "$APP_ROOT/.zmr/ios-shim"
chmod +x "$APP_ROOT/.zmr/android-shim" "$APP_ROOT/.zmr/ios-shim"
printf '{\n  "name": "Android config smoke",\n  "appId": "com.example.mobiletest",\n  "steps": [{ "action": "snapshot" }]\n}\n' > "$APP_ROOT/.zmr/android-smoke.json"
printf '{\n  "name": "iOS config smoke",\n  "appId": "com.example.mobiletest",\n  "steps": [{ "action": "snapshot" }]\n}\n' > "$APP_ROOT/.zmr/ios-smoke.json"
printf '{\n  "schemaVersion": 1,\n  "appId": "com.example.mobiletest",\n  "android": { "smokeScenario": ".zmr/android-smoke.json" },\n  "ios": { "smokeScenario": ".zmr/ios-smoke.json" },\n  "tools": {\n    "androidShimPath": ".zmr/android-shim",\n    "iosShimPath": ".zmr/ios-shim"\n  }\n}\n' > "$APP_ROOT/.zmr/config.json"

ABS_CONFIG_OUTPUT="$("$ZMR" doctor --json --config "$APP_ROOT/.zmr/config.json" --adb "$ROOT/tests/fake-adb.sh" --xcrun "$ROOT/tests/fake-xcrun.sh")"

grep -q '"ok":true' <<< "$ABS_CONFIG_OUTPUT"
grep -q '"name":"android-shim","status":"ok"' <<< "$ABS_CONFIG_OUTPUT"
grep -q '"name":"ios-shim","status":"ok"' <<< "$ABS_CONFIG_OUTPUT"
grep -q '"name":"android-smoke-scenario","status":"ok"' <<< "$ABS_CONFIG_OUTPUT"
grep -q '"name":"ios-smoke-scenario","status":"ok"' <<< "$ABS_CONFIG_OUTPUT"
grep -q "$APP_ROOT/.zmr/android-smoke.json" <<< "$ABS_CONFIG_OUTPUT"
grep -q "$APP_ROOT/.zmr/ios-smoke.json" <<< "$ABS_CONFIG_OUTPUT"
