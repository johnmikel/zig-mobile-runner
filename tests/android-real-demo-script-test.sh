#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

for args in "--out" "--app-id" "--device" "--avd" "--runs" "--trace-root" "--api" "--build-tools" "--android-sdk" "--adb" "--emulator"; do
  set +e
  missing_value_output="$("$ROOT/scripts/demo-android-real.sh" $args 2>&1)"
  missing_value_status=$?
  set -e
  if [[ "$missing_value_status" -ne 2 ]]; then
    echo "demo-android-real should exit 2 for missing value: $args" >&2
    exit 1
  fi
  grep -q -- "$args requires a value" <<< "$missing_value_output"
done

output="$("$ROOT/scripts/demo-android-real.sh" \
  --dry-run \
  --out "$TMPDIR/demo-android" \
  --device emulator-5554 \
  --avd Pixel_API_35 \
  --app-id com.example.mobiletest \
  --runs 3 \
  --trace-root "$TMPDIR/traces" 2>&1)"

python3 - "$output" "$TMPDIR" <<'PY'
import sys

output = sys.argv[1]
tmp = sys.argv[2]

assert "DRY RUN" in output
assert "Android real demo app:" in output
assert f"{tmp}/demo-android" in output
assert "create-android-demo-app.sh --out" in output
assert "--app-id com.example.mobiletest" in output
assert "adb -s emulator-5554 get-state" in output
assert "auto boot Android emulator Pixel_API_35 when emulator-5554 is not ready" in output
assert "android-emulator.sh boot --avd Pixel_API_35 --device emulator-5554" in output
assert "android-emulator.sh wait-ready --device emulator-5554" in output
assert "adb -s emulator-5554 uninstall com.example.mobiletest" in output
assert "adb -s emulator-5554 install -r" in output
assert "build/app-debug.apk" in output
assert "scripts/benchmark.sh" in output
assert "--zmr" in output
assert ".zmr/android-smoke.json" in output
assert "--device emulator-5554" in output
assert "--app-id com.example.mobiletest" in output
assert "--runs 3" in output
assert f"--trace-root {tmp}/traces" in output
assert "Android real demo complete." in output
PY

if "$ROOT/scripts/demo-android-real.sh" --dry-run --out "$TMPDIR/missing-avd" --device emulator-5554 --no-auto-boot-emulator >/tmp/zmr-android-demo-no-auto.out 2>&1; then
  echo "expected no-auto dry run to fail without a ready device" >&2
  exit 1
fi
grep -q 'device emulator-5554 is not ready and auto boot is disabled' /tmp/zmr-android-demo-no-auto.out
