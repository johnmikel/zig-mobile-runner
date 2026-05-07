#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

cat > "$TMPDIR/fake-zmr" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
platform="android"
device=""
trace_dir=""
scenario=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    run)
      shift
      scenario="${1:-}"
      shift
      ;;
    --platform)
      platform="${2:-}"
      shift 2
      ;;
    --device)
      device="${2:-}"
      shift 2
      ;;
    --trace-dir)
      trace_dir="${2:-}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
mkdir -p "$trace_dir"
case "$device" in
  failing-device)
    printf '{"seq":1,"kind":"scenario.end","payload":{"status":"failed","error":"WaitTimeout"}}\n' > "$trace_dir/events.jsonl"
    exit 1
    ;;
  *)
    printf '{"seq":1,"kind":"scenario.end","payload":{"status":"passed","platform":"%s","scenario":"%s"}}\n' "$platform" "$scenario" > "$trace_dir/events.jsonl"
    ;;
esac
SH
chmod +x "$TMPDIR/fake-zmr"
touch "$TMPDIR/android-smoke.json" "$TMPDIR/ios-smoke.json"

cat > "$TMPDIR/matrix.json" <<JSON
{
  "runs": 2,
  "appId": "com.example.mobiletest",
  "devices": [
    {
      "name": "android-api-35",
      "platform": "android",
      "serial": "emulator-5554",
      "scenario": "$TMPDIR/android-smoke.json",
      "adb": "./tests/fake-adb.sh"
    },
    {
      "name": "ios-18",
      "platform": "ios",
      "serial": "booted",
      "scenario": "$TMPDIR/ios-smoke.json",
      "xcrun": "./tests/fake-xcrun.sh",
      "iosShim": "./tests/fake-ios-shim.sh"
    }
  ]
}
JSON

ZMR_BIN="$TMPDIR/fake-zmr" "$ROOT/scripts/device-matrix.sh" \
  --matrix "$TMPDIR/matrix.json" \
  --trace-root "$TMPDIR/matrix-pass" \
  --min-pass-rate 100 \
  --max-failures 0 > "$TMPDIR/matrix-pass.out"

grep -q 'matrix: runs=4 passRate=100.00% failures=0' "$TMPDIR/matrix-pass.out"
test -f "$TMPDIR/matrix-pass/matrix.jsonl"
test -f "$TMPDIR/matrix-pass/summary.json"

python3 - "$TMPDIR/matrix-pass" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
rows = [json.loads(line) for line in (root / "matrix.jsonl").read_text().splitlines()]
summary = json.loads((root / "summary.json").read_text())
assert len(rows) == 4
assert {row["deviceName"] for row in rows} == {"android-api-35", "ios-18"}
assert {row["platform"] for row in rows} == {"android", "ios"}
assert summary["totalRuns"] == 4
assert summary["passed"] == 4
assert summary["failed"] == 0
assert summary["passRate"] == 100.0
PY

cat > "$TMPDIR/matrix-fail.json" <<JSON
{
  "runs": 1,
  "devices": [
    {
      "name": "bad-device",
      "platform": "android",
      "serial": "failing-device",
      "scenario": "$TMPDIR/android-smoke.json"
    },
    {
      "name": "good-device",
      "platform": "android",
      "serial": "emulator-5554",
      "scenario": "$TMPDIR/android-smoke.json"
    }
  ]
}
JSON

if ZMR_BIN="$TMPDIR/fake-zmr" "$ROOT/scripts/device-matrix.sh" \
  --matrix "$TMPDIR/matrix-fail.json" \
  --trace-root "$TMPDIR/matrix-fail" \
  --min-pass-rate 100 \
  --max-failures 0 > "$TMPDIR/matrix-fail.out" 2>&1; then
  echo "device matrix should fail when thresholds reject results" >&2
  exit 1
fi
grep -q 'matrix gate failed' "$TMPDIR/matrix-fail.out"
grep -q 'passRate=50.00%' "$TMPDIR/matrix-fail.out"
