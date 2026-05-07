#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

set +e
missing_output="$("$ROOT/scripts/pilot-gate.sh" --android --ios --dry-run 2>&1)"
missing_status=$?
set -e

if [[ "$missing_status" -eq 0 ]]; then
  echo "expected pilot gate to require app paths for selected platforms" >&2
  exit 1
fi

grep -q 'error: --android-app-root is required when --android is selected' <<< "$missing_output"

output="$("$ROOT/scripts/pilot-gate.sh" \
  --android \
  --ios \
  --android-app-root "$TMPDIR/android-app" \
  --android-app-id com.example.android \
  --android-device emulator-5554 \
  --android-apk "$TMPDIR/app-debug.apk" \
  --adb "$TMPDIR/adb" \
  --ios-app-root "$TMPDIR/ios-app" \
  --ios-app-id com.example.ios \
  --ios-device booted \
  --ios-app-path "$TMPDIR/Sample.app" \
  --ios-shim "$TMPDIR/ios-shim" \
  --xcrun "$TMPDIR/xcrun" \
  --trace-root "$TMPDIR/pilot-gate" \
  --runs 20 \
  --min-pass-rate 100 \
  --max-failures 0 \
  --android-max-p95-ms 30000 \
  --ios-max-p95-ms 45000 \
  --dry-run 2>&1)"

python3 - "$output" "$ROOT" "$TMPDIR" <<'PY'
import os
import sys

output = sys.argv[1]
root = os.path.realpath(sys.argv[2])
tmp = os.path.realpath(sys.argv[3])

assert "DRY RUN" in output
assert f"{root}/scripts/run-android-pilot.sh" in output
assert f"--app-root {tmp}/android-app" in output
assert "--app-id com.example.android" in output
assert "--device emulator-5554" in output
assert f"--apk {tmp}/app-debug.apk" in output
assert f"--adb {tmp}/adb" in output
assert f"--trace-root {tmp}/pilot-gate/android" in output
assert "--runs 20" in output
assert "--min-pass-rate 100" in output
assert "--max-failures 0" in output
assert "--max-p95-ms 30000" in output
assert f"{root}/scripts/run-ios-pilot.sh" in output
assert f"--app-root {tmp}/ios-app" in output
assert f"--app-path {tmp}/Sample.app" in output
assert "--app-id com.example.ios" in output
assert "--device booted" in output
assert f"--ios-shim {tmp}/ios-shim" in output
assert f"--xcrun {tmp}/xcrun" in output
assert f"--trace-root {tmp}/pilot-gate/ios" in output
assert "--max-p95-ms 45000" in output
PY

android_only="$("$ROOT/scripts/pilot-gate.sh" \
  --android \
  --android-app-root "$TMPDIR/android-app" \
  --skip-emulator \
  --skip-metro \
  --trace-root "$TMPDIR/android-only" \
  --dry-run 2>&1)"

python3 - "$android_only" "$ROOT" "$TMPDIR" <<'PY'
import os
import sys

output = sys.argv[1]
root = os.path.realpath(sys.argv[2])
tmp = os.path.realpath(sys.argv[3])

assert f"{root}/scripts/run-android-pilot.sh" in output
assert f"{root}/scripts/run-ios-pilot.sh" not in output
assert "--skip-emulator" in output
assert "--skip-metro" in output
assert f"--trace-root {tmp}/android-only/android" in output
PY

APP_CWD="$TMPDIR/app-cwd"
mkdir -p "$APP_CWD/bin" "$APP_CWD/.zmr" "$APP_CWD/build"

app_cwd_output="$(cd "$APP_CWD" && "$ROOT/scripts/pilot-gate.sh" \
  --android \
  --ios \
  --android-app-root . \
  --android-apk ./build/app-debug.apk \
  --adb ./bin/adb \
  --ios-app-root . \
  --ios-app-path ./build/Sample.app \
  --ios-shim ./.zmr/ios-shim \
  --xcrun ./bin/xcrun \
  --trace-root traces/pilot \
  --dry-run 2>&1)"

python3 - "$app_cwd_output" "$ROOT" "$APP_CWD" <<'PY'
import os
import sys

output = sys.argv[1]
root = os.path.realpath(sys.argv[2])
app = os.path.realpath(sys.argv[3])

assert f"{root}/scripts/run-android-pilot.sh" in output
assert f"{root}/scripts/run-ios-pilot.sh" in output
assert f"--app-root {app}" in output
assert f"--apk {app}/build/app-debug.apk" in output
assert f"--adb {app}/bin/adb" in output
assert f"--app-path {app}/build/Sample.app" in output
assert f"--ios-shim {app}/.zmr/ios-shim" in output
assert f"--xcrun {app}/bin/xcrun" in output
assert f"--trace-root {app}/traces/pilot/android" in output
assert f"--trace-root {app}/traces/pilot/ios" in output
PY
