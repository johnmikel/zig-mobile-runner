#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

APP_ROOT="$TMPDIR/android-app"
mkdir -p "$APP_ROOT/android/app/build/outputs/apk/debug"
touch "$APP_ROOT/.env.test"
touch "$APP_ROOT/android/app/build/outputs/apk/debug/app-debug.apk"

EMPTY_ADB="$TMPDIR/fake-adb-empty.sh"
cat > "$EMPTY_ADB" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  devices) printf 'List of devices attached\n' ;;
  version) printf 'Android Debug Bridge version 1.0.41\n' ;;
  *) exit 2 ;;
esac
SH
chmod +x "$EMPTY_ADB"

set +e
missing_device_output="$("$ROOT/scripts/run-android-pilot.sh" \
  --skip-emulator \
  --skip-metro \
  --app-root "$APP_ROOT" \
  --adb "$EMPTY_ADB" \
  --device emulator-5554 \
  --trace-root "$TMPDIR/pilot-missing-device" 2>&1)"
missing_device_status=$?
set -e

if [[ "$missing_device_status" -eq 0 ]]; then
  echo "expected Android pilot preflight to fail when the requested device is absent" >&2
  exit 1
fi

grep -q 'no Android device found: emulator-5554' <<< "$missing_device_output"
grep -q 'setup.android.no_devices' <<< "$missing_device_output"
grep -q 'zmr doctor --json' <<< "$missing_device_output"

output="$("$ROOT/scripts/run-android-pilot.sh" \
  --dry-run \
  --skip-emulator \
  --skip-metro \
  --app-root "$APP_ROOT" \
  --app-id com.example.override \
  --device emulator-5554 \
  --trace-root "$TMPDIR/pilot" 2>&1)"

python3 - "$output" "$APP_ROOT" "$TMPDIR/pilot" <<'PY'
import sys

output = sys.argv[1]
app_root = sys.argv[2]
trace_root = sys.argv[3]

assert "DRY RUN" in output
assert "--adb" not in output
assert "zmr validate examples/android-app-auth-probe.json" in output
assert "zmr validate examples/android-app-login-smoke.json" in output
assert f"adb -s emulator-5554 install -r {app_root}/android/app/build/outputs/apk/debug/app-debug.apk" in output
assert "zmr run examples/android-app-auth-probe.json --device emulator-5554" in output
assert "zmr run examples/android-app-login-smoke.json --device emulator-5554" in output
assert "--app-id com.example.override" in output
assert f"--trace-dir {trace_root}/auth" in output
assert f"--trace-dir {trace_root}/login-smoke" in output
assert "zmr export" in output
assert "--redact" in output
assert ".env.test" in output
assert "dotenv" not in output.lower()
PY

CUSTOM_ADB="$TMPDIR/custom-adb.sh"
touch "$CUSTOM_ADB"
chmod +x "$CUSTOM_ADB"

custom_adb_output="$("$ROOT/scripts/run-android-pilot.sh" \
  --dry-run \
  --skip-emulator \
  --skip-metro \
  --app-root "$APP_ROOT" \
  --adb "$CUSTOM_ADB" \
  --device emulator-5554 \
  --trace-root "$TMPDIR/pilot-custom-adb" 2>&1)"

python3 - "$custom_adb_output" "$CUSTOM_ADB" <<'PY'
import sys

output = sys.argv[1]
custom_adb = sys.argv[2]

assert f"{custom_adb} -s emulator-5554 install -r" in output
assert f"zmr run examples/android-app-auth-probe.json --device emulator-5554 --app-id com.example.mobiletest --trace-dir" in output
assert f"--adb {custom_adb}" in output
assert f"zmr run examples/android-app-login-smoke.json --device emulator-5554 --app-id com.example.mobiletest --trace-dir" in output
PY

ANDROID_HOME="$TMPDIR/android-sdk"
mkdir -p "$ANDROID_HOME/emulator"
touch "$ANDROID_HOME/emulator/emulator"
chmod +x "$ANDROID_HOME/emulator/emulator"

lifecycle_output="$(ANDROID_HOME="$ANDROID_HOME" "$ROOT/scripts/run-android-pilot.sh" \
  --dry-run \
  --skip-metro \
  --reset-emulator \
  --restore-snapshot zmr-clean \
  --screen-record \
  --avd Small_Phone \
  --app-root "$APP_ROOT" \
  --device emulator-5554 \
  --trace-root "$TMPDIR/pilot-lifecycle" 2>&1)"

python3 - "$lifecycle_output" "$ANDROID_HOME" <<'PY'
import sys

output = sys.argv[1]
android_home = sys.argv[2]

assert "adb -s emulator-5554 emu kill" in output
assert f"{android_home}/emulator/emulator -avd Small_Phone" in output
assert "-snapshot zmr-clean" in output
assert "-no-snapshot-save" in output
assert "wait for adb device emulator-5554" in output
assert "wait for Android boot completion on emulator-5554" in output
assert "adb -s emulator-5554 shell rm -f /sdcard/zmr-pilot-screenrecord.mp4" in output
assert "adb -s emulator-5554 shell screenrecord /sdcard/zmr-pilot-screenrecord.mp4" in output
assert "adb -s emulator-5554 pull /sdcard/zmr-pilot-screenrecord.mp4" in output
assert "screenrecord.mp4" in output
PY

benchmark_output="$("$ROOT/scripts/run-android-pilot.sh" \
  --dry-run \
  --skip-emulator \
  --skip-metro \
  --app-root "$APP_ROOT" \
  --app-id com.example.override \
  --device emulator-5554 \
  --trace-root "$TMPDIR/pilot-benchmark" \
  --runs 20 \
  --min-pass-rate 100 \
  --max-failures 0 \
  --max-p95-ms 30000 2>&1)"

python3 - "$benchmark_output" "$TMPDIR/pilot-benchmark" <<'PY'
import sys

output = sys.argv[1]
trace_root = sys.argv[2]

assert "benchmark.sh --zmr examples/android-app-auth-probe.json" in output
assert "benchmark.sh --zmr examples/android-app-login-smoke.json" in output
assert "--runs 20" in output
assert "--app-id com.example.override" in output
assert "--min-pass-rate 100" in output
assert "--max-failures 0" in output
assert "--max-p95-ms 30000" in output
assert f"--trace-root {trace_root}/bench-auth" in output
assert f"--trace-root {trace_root}/bench-login-smoke" in output
PY

custom_adb_benchmark_output="$("$ROOT/scripts/run-android-pilot.sh" \
  --dry-run \
  --skip-emulator \
  --skip-metro \
  --app-root "$APP_ROOT" \
  --adb "$CUSTOM_ADB" \
  --device emulator-5554 \
  --trace-root "$TMPDIR/pilot-custom-adb-benchmark" \
  --runs 2 2>&1)"

python3 - "$custom_adb_benchmark_output" "$CUSTOM_ADB" <<'PY'
import sys

output = sys.argv[1]
custom_adb = sys.argv[2]

assert "benchmark.sh --zmr examples/android-app-auth-probe.json" in output
assert "benchmark.sh --zmr examples/android-app-login-smoke.json" in output
assert f"--adb {custom_adb}" in output
PY
