#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

for args in "--out" "--app-id" "--api" "--build-tools" "--android-sdk"; do
  set +e
  missing_value_output="$("$ROOT/scripts/create-android-demo-app.sh" $args 2>&1)"
  missing_value_status=$?
  set -e
  if [[ "$missing_value_status" -ne 2 ]]; then
    echo "create-android-demo-app should exit 2 for missing value: $args" >&2
    exit 1
  fi
  grep -q -- "$args requires a value" <<< "$missing_value_output"
done

output="$("$ROOT/scripts/create-android-demo-app.sh" \
  --dry-run \
  --out "$TMPDIR/android-demo" \
  --app-id com.example.mobiletest \
  --api 35 \
  --build-tools 35.0.1 2>&1)"

python3 - "$output" "$TMPDIR" <<'PY'
import sys

output = sys.argv[1]
tmp = sys.argv[2]

required = [
    "DRY RUN",
    f"Android demo app: {tmp}/android-demo",
    "Android demo APK:",
    "AndroidManifest.xml",
    "MainActivity.java",
    "aapt2 compile",
    "aapt2 link",
    "javac",
    "d8",
    "apksigner sign",
    ".zmr/android-smoke.json",
]

for needle in required:
    assert needle in output, needle
PY

if command -v javac >/dev/null 2>&1 && [[ -d "${ANDROID_HOME:-$HOME/Library/Android/sdk}" ]]; then
  "$ROOT/scripts/create-android-demo-app.sh" \
    --out "$TMPDIR/android-demo-real" \
    --app-id com.example.mobiletest \
    --api 35 \
    --build-tools 35.0.1
  "$ROOT/scripts/create-android-demo-app.sh" \
    --out "$TMPDIR/android-demo-real" \
    --app-id com.example.mobiletest \
    --api 35 \
    --build-tools 35.0.1 >/dev/null

  test -f "$TMPDIR/android-demo-real/android/AndroidManifest.xml"
  test -f "$TMPDIR/android-demo-real/android/src/dev/zmr/demo/MainActivity.java"
  test -f "$TMPDIR/android-demo-real/build/app-debug.apk"
  test -f "$TMPDIR/android-demo-real/.zmr/android-smoke.json"

  "$ROOT/zig-out/bin/zmr" validate "$TMPDIR/android-demo-real/.zmr/android-smoke.json"
  python3 - "$TMPDIR/android-demo-real/.zmr/android-smoke.json" <<'PY'
import json
import sys

scenario = json.load(open(sys.argv[1], encoding="utf-8"))
assert scenario["steps"][1]["action"] == "waitVisible"
assert scenario["steps"][1]["timeoutMs"] == 30000
tap = scenario["steps"][2]
assert tap["action"] == "tap"
assert tap["selector"]["resourceId"] == "com.example.mobiletest:id/continue_button"
assert scenario["steps"][3]["timeoutMs"] == 10000
assert scenario["steps"][4]["selector"]["resourceId"] == "com.example.mobiletest:id/demo_input"
PY
  apk_listing="$(unzip -l "$TMPDIR/android-demo-real/build/app-debug.apk")"
  grep -q 'classes.dex' <<< "$apk_listing"
fi
