#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

RC_TEST="$TMPDIR/rc-test"
RC_LOCAL="$TMPDIR/rc-local"
RC_HARDWARE="$TMPDIR/rc-hardware"
RC_LOCAL_ANDROID="$TMPDIR/rc-local-android"

output="$("$ROOT/scripts/release-candidate.sh" --dry-run --mode all --evidence-dir "$RC_TEST" --runs 20 2>&1)"

python3 - "$output" "$RC_TEST" <<'PY'
import sys

output = sys.argv[1]
rc_test = sys.argv[2]

required = [
    "release candidate mode: all",
    f"release candidate evidence: {rc_test}",
    "./scripts/release-gate.sh",
    f"./scripts/create-android-demo-app.sh --out {rc_test}/android-demo",
    f"./scripts/demo-ios-real.sh --out {rc_test}/ios-demo --device booted --runs 5 --trace-root {rc_test}/ios-demo/traces/pilot --cleanup-build-products",
    f"./scripts/pilot-gate.sh --android --ios --android-app-root /path/to/mobile-app --android-app-id com.example.mobiletest --android-device emulator-5554 --ios-app-root /path/to/mobile-app --ios-app-path /path/to/mobile-app/build/Debug-iphonesimulator/Sample.app --ios-app-id com.example.mobiletest --ios-device booted --ios-shim /path/to/mobile-app/.zmr/ios-shim --xcrun xcrun --runs 20 --min-pass-rate 100 --max-failures 0 --trace-root {rc_test}/hardware-pilot --evidence-out {rc_test}/hardware-pilot/evidence.jsonl",
    f"./scripts/pilot-gate.sh --ios --ios-device-type physical --ios-device \\<physical-device-id\\> --ios-app-root /path/to/mobile-app --ios-app-path /path/to/mobile-app/build/Release-iphoneos/Sample.ipa --ios-app-id com.example.mobiletest --ios-shim /path/to/mobile-app/.zmr/ios-shim --xcrun xcrun --runs 20 --min-pass-rate 100 --max-failures 0 --trace-root {rc_test}/ios-physical-pilot --evidence-out {rc_test}/ios-physical-pilot/evidence.jsonl",
    f"wrote {rc_test}/evidence.jsonl",
    f"wrote {rc_test}/summary.md",
]

for needle in required:
    assert needle in output, needle

assert "hardware mode requires replacing placeholder paths before publish" in output
PY

python3 - "$RC_TEST/evidence.jsonl" <<'PY'
import json
import sys

rows = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8") if line.strip()]
by_name = {row["name"]: row for row in rows}

android = by_name["Android hardware pilot"]
assert android["androidAppRoot"] == "/path/to/mobile-app"
assert android["androidAppId"] == "com.example.mobiletest"
assert android["androidDeviceId"] == "emulator-5554"
assert android["runs"] == 20
assert android["minPassRate"] == 100
assert android["maxFailures"] == 0

ios_sim = by_name["iOS simulator hardware pilot"]
assert ios_sim["iosAppRoot"] == "/path/to/mobile-app"
assert ios_sim["iosAppPath"] == "/path/to/mobile-app/build/Debug-iphonesimulator/Sample.app"
assert ios_sim["iosAppId"] == "com.example.mobiletest"
assert ios_sim["iosDeviceId"] == "booted"
assert ios_sim["runs"] == 20
assert ios_sim["minPassRate"] == 100
assert ios_sim["maxFailures"] == 0

ios_physical = by_name["iOS physical hardware pilot"]
assert ios_physical["iosAppRoot"] == "/path/to/mobile-app"
assert ios_physical["iosAppPath"] == "/path/to/mobile-app/build/Release-iphoneos/Sample.ipa"
assert ios_physical["iosAppId"] == "com.example.mobiletest"
assert ios_physical["iosDeviceId"] == "<physical-device-id>"
assert ios_physical["runs"] == 20
assert ios_physical["minPassRate"] == 100
assert ios_physical["maxFailures"] == 0
PY

local_output="$("$ROOT/scripts/release-candidate.sh" --dry-run --mode local --evidence-dir "$RC_LOCAL" 2>&1)"
grep -q './scripts/release-gate.sh' <<< "$local_output"
grep -q './scripts/create-android-demo-app.sh' <<< "$local_output"
grep -q './scripts/demo-ios-real.sh' <<< "$local_output"
grep -q '## Readiness' "$RC_LOCAL/summary.md"
grep -q 'scripts/release-readiness.sh --evidence' "$RC_LOCAL/summary.md"
grep -q -- '--target dev-preview' "$RC_LOCAL/summary.md"
grep -q 'Blocked requirements' "$RC_LOCAL/summary.md"
if grep -q 'run-android-pilot.sh' <<< "$local_output"; then
  echo "local release-candidate mode should not include hardware pilots" >&2
  exit 1
fi

hardware_output="$("$ROOT/scripts/release-candidate.sh" --dry-run --mode hardware --evidence-dir "$RC_HARDWARE" --runs 3 2>&1)"
grep -q './scripts/pilot-gate.sh --android --ios' <<< "$hardware_output"
grep -q './scripts/pilot-gate.sh --ios --ios-device-type physical --ios-device' <<< "$hardware_output"
grep -q -- '--runs 3' <<< "$hardware_output"
if grep -q './scripts/release-gate.sh' <<< "$hardware_output"; then
  echo "hardware release-candidate mode should not rerun local release gate" >&2
  exit 1
fi

RC_HARDWARE_XCRUN="$TMPDIR/rc-hardware-xcrun"
hardware_xcrun_output="$("$ROOT/scripts/release-candidate.sh" --dry-run --mode hardware --evidence-dir "$RC_HARDWARE_XCRUN" --xcrun /tmp/custom-xcrun 2>&1)"
grep -q './scripts/pilot-gate.sh --android --ios .*--xcrun /tmp/custom-xcrun' <<< "$hardware_xcrun_output"
grep -Fq './scripts/pilot-gate.sh --ios --ios-device-type physical --ios-device \<physical-device-id\>' <<< "$hardware_xcrun_output"
grep -q './scripts/pilot-gate.sh --ios .*--xcrun /tmp/custom-xcrun' <<< "$hardware_xcrun_output"

RC_SPACES="$TMPDIR/rc spaces"
APP_ROOT_SPACES="$TMPDIR/app root"
APP_PATH_SPACES="$TMPDIR/app root/build/Debug App.app"
IPA_PATH_SPACES="$TMPDIR/app root/build/Release App.ipa"
SHIM_SPACES="$TMPDIR/app root/.zmr/ios shim"
XCRUN_SPACES="$TMPDIR/custom xcrun"
"$ROOT/scripts/release-candidate.sh" \
  --dry-run \
  --mode hardware \
  --evidence-dir "$RC_SPACES" \
  --android-app-root "$APP_ROOT_SPACES" \
  --android-app-id com.example.demo \
  --android-device emulator-5554 \
  --ios-app-root "$APP_ROOT_SPACES" \
  --ios-app-path "$APP_PATH_SPACES" \
  --ios-app-id com.example.demo \
  --ios-device booted \
  --ios-shim "$SHIM_SPACES" \
  --xcrun "$XCRUN_SPACES" \
  --ios-physical-app-root "$APP_ROOT_SPACES" \
  --ios-physical-app-path "$IPA_PATH_SPACES" \
  --ios-physical-app-id com.example.demo \
  --ios-physical-device ios-ready \
  --ios-physical-shim "$SHIM_SPACES" >/dev/null
python3 - "$RC_SPACES/evidence.jsonl" "$APP_ROOT_SPACES" "$APP_PATH_SPACES" "$IPA_PATH_SPACES" "$SHIM_SPACES" "$XCRUN_SPACES" <<'PY'
import json
import os
import shlex
import sys

evidence, app_root, app_path, ipa_path, shim, xcrun = sys.argv[1:]
app_root = os.path.realpath(app_root)
app_path = os.path.realpath(app_path)
ipa_path = os.path.realpath(ipa_path)
shim = os.path.realpath(shim)
xcrun = os.path.realpath(xcrun)
rows = [json.loads(line) for line in open(evidence, encoding="utf-8") if line.strip()]
by_name = {row["name"]: row for row in rows}

def flag_value(parts, flag):
    index = parts.index(flag)
    return parts[index + 1]

assert flag_value(shlex.split(by_name["physical iOS readiness"]["command"]), "--xcrun") == xcrun

android = shlex.split(by_name["Android hardware pilot"]["command"])
assert flag_value(android, "--app-root") == app_root

ios_sim = shlex.split(by_name["iOS simulator hardware pilot"]["command"])
assert flag_value(ios_sim, "--app-root") == app_root
assert flag_value(ios_sim, "--app-path") == app_path
assert flag_value(ios_sim, "--ios-shim") == shim
assert flag_value(ios_sim, "--xcrun") == xcrun

ios_physical = shlex.split(by_name["iOS physical hardware pilot"]["command"])
assert flag_value(ios_physical, "--app-root") == app_root
assert flag_value(ios_physical, "--app-path") == ipa_path
assert flag_value(ios_physical, "--ios-shim") == shim
assert flag_value(ios_physical, "--xcrun") == xcrun
PY
python3 - "$RC_SPACES/summary.md" "$RC_SPACES/evidence.jsonl" <<'PY'
import shlex
import sys

summary, evidence = sys.argv[1:]
readiness_lines = [
    line.strip().strip("`")
    for line in open(summary, encoding="utf-8")
    if line.startswith("`./scripts/release-readiness.sh --evidence ")
]
assert len(readiness_lines) == 1
parts = shlex.split(readiness_lines[0])
assert parts == [
    "./scripts/release-readiness.sh",
    "--evidence",
    evidence,
    "--target",
    "production",
]
PY

RC_LOCAL_DEMO_RUNS="$TMPDIR/rc-local-demo-runs"
local_demo_runs_output="$("$ROOT/scripts/release-candidate.sh" --dry-run --mode local --evidence-dir "$RC_LOCAL_DEMO_RUNS" --local-ios-demo-runs 7 2>&1)"
grep -q -- "./scripts/demo-ios-real.sh --out $RC_LOCAL_DEMO_RUNS/ios-demo --device booted --runs 7 --trace-root $RC_LOCAL_DEMO_RUNS/ios-demo/traces/pilot --cleanup-build-products" <<< "$local_demo_runs_output"

local_android_output="$("$ROOT/scripts/release-candidate.sh" --dry-run --mode local --evidence-dir "$RC_LOCAL_ANDROID" --local-android-avd Small_Phone --local-android-device emulator-5556 --local-android-demo-runs 7 2>&1)"
grep -q -- "./scripts/demo-android-real.sh --out $RC_LOCAL_ANDROID/android-demo --device emulator-5556 --avd Small_Phone --runs 7 --trace-root $RC_LOCAL_ANDROID/android-demo/traces/pilot" <<< "$local_android_output"
if grep -q './scripts/create-android-demo-app.sh --out' <<< "$local_android_output"; then
  echo "local release-candidate mode should use the real Android demo wrapper when --local-android-avd is provided" >&2
  exit 1
fi

for args in \
  "--mode" \
  "--evidence-dir" \
  "--runs" \
  "--local-android-demo-runs" \
  "--local-android-device" \
  "--local-android-avd" \
  "--local-ios-demo-runs" \
  "--android-app-root" \
  "--android-app-id" \
  "--android-device" \
  "--ios-app-root" \
  "--ios-app-path" \
  "--ios-app-id" \
  "--ios-device" \
  "--ios-shim" \
  "--xcrun" \
  "--ios-physical-app-root" \
  "--ios-physical-app-path" \
  "--ios-physical-app-id" \
  "--ios-physical-device" \
  "--ios-physical-shim"; do
  set +e
  missing_value_output="$("$ROOT/scripts/release-candidate.sh" $args --dry-run 2>&1)"
  missing_value_status=$?
  set -e
  if [[ "$missing_value_status" -ne 2 ]]; then
    echo "release candidate should exit 2 for missing value: $args" >&2
    exit 1
  fi
  grep -q -- "$args requires a value" <<< "$missing_value_output"
done

for args in "--zmr" "--xcrun" "--device" "--evidence-out"; do
  set +e
  missing_value_output="$("$ROOT/scripts/assert-ios-physical-ready.sh" $args 2>&1)"
  missing_value_status=$?
  set -e
  if [[ "$missing_value_status" -ne 2 ]]; then
    echo "physical readiness should exit 2 for missing value: $args" >&2
    exit 1
  fi
  grep -q -- "$args requires a value" <<< "$missing_value_output"
done

FAKE_ZMR_DISCONNECTED="$TMPDIR/fake-zmr-disconnected.sh"
cat > "$FAKE_ZMR_DISCONNECTED" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" != "devices --json --platform ios --ios-device-type physical" ]]; then
  echo "unexpected zmr args: $*" >&2
  exit 2
fi
printf '{"platform":"ios","count":1,"devices":[{"serial":"ios-1","state":"disconnected","ready":false}]}\n'
SH
chmod +x "$FAKE_ZMR_DISCONNECTED"

set +e
not_ready_output="$("$ROOT/scripts/assert-ios-physical-ready.sh" --zmr "$FAKE_ZMR_DISCONNECTED" --device ios-1 2>&1)"
not_ready_status=$?
set -e

if [[ "$not_ready_status" -eq 0 ]]; then
  echo "expected physical readiness assertion to fail when the requested device is not ready" >&2
  exit 1
fi
grep -q 'setup.ios.physical_device_not_ready' <<< "$not_ready_output"
grep -q 'ios-1' <<< "$not_ready_output"
grep -q 'disconnected' <<< "$not_ready_output"

FAKE_ZMR_READY="$TMPDIR/fake-zmr-ready.sh"
cat > "$FAKE_ZMR_READY" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '{"platform":"ios","count":1,"devices":[{"serial":"ios-ready","state":"connected","ready":true}]}\n'
SH
chmod +x "$FAKE_ZMR_READY"

ready_output="$("$ROOT/scripts/assert-ios-physical-ready.sh" --zmr "$FAKE_ZMR_READY" --device ios-ready 2>&1)"
grep -q 'physical iOS device ready: ios-ready' <<< "$ready_output"

FAKE_ZMR_XCRUN="$TMPDIR/fake-zmr-xcrun.sh"
cat > "$FAKE_ZMR_XCRUN" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" != "devices --json --platform ios --ios-device-type physical --xcrun /tmp/custom-xcrun" ]]; then
  echo "unexpected zmr args: $*" >&2
  exit 2
fi
printf '{"platform":"ios","count":1,"devices":[{"serial":"ios-xcrun","state":"connected","ready":true}]}\n'
SH
chmod +x "$FAKE_ZMR_XCRUN"

xcrun_output="$("$ROOT/scripts/assert-ios-physical-ready.sh" --zmr "$FAKE_ZMR_XCRUN" --xcrun /tmp/custom-xcrun --device ios-xcrun 2>&1)"
grep -q 'physical iOS device ready: ios-xcrun' <<< "$xcrun_output"

READY_EVIDENCE="$TMPDIR/ios-ready-evidence.jsonl"
"$ROOT/scripts/assert-ios-physical-ready.sh" --zmr "$FAKE_ZMR_READY" --device ios-ready --evidence-out "$READY_EVIDENCE" >/dev/null
python3 - "$READY_EVIDENCE" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    rows = [json.loads(line) for line in fh if line.strip()]

assert len(rows) == 1
row = rows[0]
assert row["name"] == "physical iOS readiness"
assert row["mode"] == "ios-physical-ready"
assert row["status"] == "passed"
assert row["deviceId"] == "ios-ready"
assert row["command"].endswith("--device ios-ready")
assert isinstance(row["durationMs"], int)
PY

FAKE_ZMR_FLAKY="$TMPDIR/fake-zmr-flaky.sh"
FLAKY_STATE="$TMPDIR/flaky-count"
cat > "$FAKE_ZMR_FLAKY" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
count=0
if [[ -f "$ZMR_FLAKY_STATE" ]]; then
  count="$(cat "$ZMR_FLAKY_STATE")"
fi
count="$((count + 1))"
printf '%s' "$count" > "$ZMR_FLAKY_STATE"
if [[ "$count" -lt 2 ]]; then
  echo "transient CoreDevice failure" >&2
  exit 1
fi
printf '{"platform":"ios","count":1,"devices":[{"serial":"ios-flaky","state":"connected","ready":true}]}\n'
SH
chmod +x "$FAKE_ZMR_FLAKY"

flaky_output="$(ZMR_FLAKY_STATE="$FLAKY_STATE" ZMR_IOS_READY_RETRY_DELAY_SECONDS=0 "$ROOT/scripts/assert-ios-physical-ready.sh" --zmr "$FAKE_ZMR_FLAKY" --device ios-flaky 2>&1)"
grep -q 'physical iOS device ready: ios-flaky' <<< "$flaky_output"
grep -q '^2$' "$FLAKY_STATE"

if "$ROOT/scripts/release-candidate.sh" --mode nope --dry-run >/tmp/zmr-rc-invalid.out 2>&1; then
  echo "invalid release-candidate mode should fail" >&2
  exit 1
fi
grep -q -- '--mode must be local, hardware, or all' /tmp/zmr-rc-invalid.out
