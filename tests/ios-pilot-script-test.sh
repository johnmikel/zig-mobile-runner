#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

APP_ROOT="$TMPDIR/ios-app"
APP_PATH="$APP_ROOT/build/Debug-iphonesimulator/Sample.app"
mkdir -p "$APP_PATH"

EMPTY_XCRUN="$TMPDIR/fake-xcrun-empty.sh"
cat > "$EMPTY_XCRUN" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--version" ]]; then
  printf 'xcrun version 70\n'
  exit 0
fi
if [[ "${1:-}" == "simctl" && "${2:-}" == "list" && "${3:-}" == "devices" && "${4:-}" == "--json" ]]; then
  printf '{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-5":[]}}\n'
  exit 0
fi
exit 2
SH
chmod +x "$EMPTY_XCRUN"

set +e
missing_sim_output="$("$ROOT/scripts/run-ios-pilot.sh" \
  --app-root "$APP_ROOT" \
  --app-path "$APP_PATH" \
  --device booted \
  --xcrun "$EMPTY_XCRUN" \
  --trace-root "$TMPDIR/pilot-missing-sim" 2>&1)"
missing_sim_status=$?
set -e

if [[ "$missing_sim_status" -eq 0 ]]; then
  echo "expected iOS pilot preflight to fail when no booted simulator exists" >&2
  exit 1
fi

grep -q 'no booted iOS simulator found' <<< "$missing_sim_output"
grep -q 'setup.ios.no_booted_simulators' <<< "$missing_sim_output"
grep -q 'zmr doctor --json' <<< "$missing_sim_output"

output="$("$ROOT/scripts/run-ios-pilot.sh" \
  --dry-run \
  --app-root "$APP_ROOT" \
  --app-path "$APP_PATH" \
  --device fake-ios-1 \
  --ios-shim ./tests/fake-ios-shim.sh \
  --trace-root "$TMPDIR/pilot" 2>&1)"

python3 - "$output" "$APP_PATH" "$TMPDIR/pilot" <<'PY'
import sys

output = sys.argv[1]
app_path = sys.argv[2]
trace_root = sys.argv[3]

assert "DRY RUN" in output
assert "zmr validate examples/ios-smoke.json" in output
assert "zmr validate examples/ios-shim-smoke.json" in output
assert f"xcrun simctl install fake-ios-1 {app_path}" in output
assert "zmr run examples/ios-smoke.json --platform ios --device fake-ios-1" in output
assert "zmr run examples/ios-shim-smoke.json --platform ios --device fake-ios-1" in output
assert "--ios-shim ./tests/fake-ios-shim.sh" in output
assert f"--trace-dir {trace_root}/ios-smoke" in output
assert f"--trace-dir {trace_root}/ios-shim-smoke" in output
assert "zmr report" in output
assert "zmr export" in output
assert "ios-shim-smoke-redacted.zmrtrace" in output
assert "--redact" in output
PY

benchmark_output="$("$ROOT/scripts/run-ios-pilot.sh" \
  --dry-run \
  --app-root "$APP_ROOT" \
  --app-path "$APP_PATH" \
  --device fake-ios-1 \
  --app-id com.example.override \
  --xcrun ./tests/fake-xcrun.sh \
  --ios-shim ./tests/fake-ios-shim.sh \
  --trace-root "$TMPDIR/pilot-benchmark" \
  --runs 20 \
  --min-pass-rate 100 \
  --max-failures 0 \
  --max-p95-ms 45000 2>&1)"

python3 - "$benchmark_output" "$APP_PATH" "$TMPDIR/pilot-benchmark" <<'PY'
import sys

output = sys.argv[1]
app_path = sys.argv[2]
trace_root = sys.argv[3]

assert f"./tests/fake-xcrun.sh simctl install fake-ios-1 {app_path}" in output
assert "benchmark.sh --zmr examples/ios-smoke.json" in output
assert "benchmark.sh --zmr examples/ios-shim-smoke.json" in output
assert "--platform ios" in output
assert "--app-id com.example.override" in output
assert "--xcrun ./tests/fake-xcrun.sh" in output
assert "--ios-shim ./tests/fake-ios-shim.sh" in output
assert "--runs 20" in output
assert "--min-pass-rate 100" in output
assert "--max-failures 0" in output
assert "--max-p95-ms 45000" in output
assert f"--trace-root {trace_root}/ios-smoke-benchmark" in output
assert f"--trace-root {trace_root}/ios-shim-smoke-benchmark" in output
PY
