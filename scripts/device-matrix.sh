#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZMR_BIN="${ZMR_BIN:-$(command -v zmr 2>/dev/null || printf '%s' "$ROOT/zig-out/bin/zmr")}"
MATRIX=""
TRACE_ROOT="${TRACE_ROOT:-$ROOT/traces/matrix-$(date +%Y%m%d-%H%M%S)}"
MIN_PASS_RATE="${MIN_PASS_RATE:-}"
MAX_FAILURES="${MAX_FAILURES:-}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/device-matrix.sh --matrix <matrix.json> [--trace-root <dir>] [gate options]

Gate options:
  --min-pass-rate <pct>  Minimum total pass rate percentage.
  --max-failures <n>     Maximum total failed matrix runs.

Matrix format:
  {
    "runs": 2,
    "appId": "com.example.mobiletest",
    "devices": [
      {
        "name": "android-api-35",
        "platform": "android",
        "serial": "emulator-5554",
        "scenario": ".zmr/android-smoke.json",
        "adb": "adb",
        "androidShim": ".zmr/android-shim"
      },
      {
        "name": "ios-18",
        "platform": "ios",
        "serial": "booted",
        "scenario": ".zmr/ios-smoke.json",
        "xcrun": "xcrun",
        "iosShim": ".zmr/ios-shim"
      }
    ]
  }
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --matrix)
      MATRIX="${2:-}"
      shift 2
      ;;
    --trace-root)
      TRACE_ROOT="${2:-}"
      shift 2
      ;;
    --min-pass-rate)
      MIN_PASS_RATE="${2:-}"
      shift 2
      ;;
    --max-failures)
      MAX_FAILURES="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$MATRIX" ]]; then
  echo "--matrix is required" >&2
  usage >&2
  exit 2
fi

if [[ ! -f "$MATRIX" ]]; then
  echo "matrix file not found: $MATRIX" >&2
  exit 2
fi

if [[ ! -x "$ZMR_BIN" ]]; then
  echo "zmr binary is not executable: $ZMR_BIN" >&2
  exit 2
fi

validate_optional_number() {
  local name="$1"
  local value="$2"
  if [[ -n "$value" && ! "$value" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    echo "$name must be a non-negative number" >&2
    exit 2
  fi
}

validate_optional_integer() {
  local name="$1"
  local value="$2"
  if [[ -n "$value" && ! "$value" =~ ^[0-9]+$ ]]; then
    echo "$name must be a non-negative integer" >&2
    exit 2
  fi
}

validate_optional_number "--min-pass-rate" "$MIN_PASS_RATE"
validate_optional_integer "--max-failures" "$MAX_FAILURES"

mkdir -p "$TRACE_ROOT"
ROWS="$TRACE_ROOT/matrix.rows.tsv"
RESULTS="$TRACE_ROOT/matrix.jsonl"
SUMMARY="$TRACE_ROOT/summary.json"
: > "$RESULTS"

python3 - "$MATRIX" > "$ROWS" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    matrix = json.load(fh)

runs = int(matrix.get("runs", 1))
if runs < 1:
    raise SystemExit("matrix.runs must be >= 1")

default_app_id = matrix.get("appId", "")
devices = matrix.get("devices")
if not isinstance(devices, list) or not devices:
    raise SystemExit("matrix.devices must be a non-empty array")

fields = [
    "name",
    "platform",
    "serial",
    "scenario",
    "appId",
    "adb",
    "androidShim",
    "xcrun",
    "iosShim",
]

for index, device in enumerate(devices):
    if not isinstance(device, dict):
        raise SystemExit(f"matrix.devices[{index}] must be an object")
    row = {}
    row["name"] = device.get("name") or device.get("serial") or f"device-{index + 1}"
    row["platform"] = device.get("platform", "android")
    row["serial"] = device.get("serial", "")
    row["scenario"] = device.get("scenario", "")
    row["appId"] = device.get("appId", default_app_id)
    row["adb"] = device.get("adb", "")
    row["androidShim"] = device.get("androidShim", "")
    row["xcrun"] = device.get("xcrun", "")
    row["iosShim"] = device.get("iosShim", "")
    if row["platform"] not in {"android", "ios"}:
        raise SystemExit(f"matrix.devices[{index}].platform must be android or ios")
    if not row["serial"]:
        raise SystemExit(f"matrix.devices[{index}].serial is required")
    if not row["scenario"]:
        raise SystemExit(f"matrix.devices[{index}].scenario is required")
    for run in range(1, runs + 1):
        values = [str(run)] + [str(row[field]).replace("\t", " ") for field in fields]
        print("\t".join(values))
PY

slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9._-]+/-/g; s/^-+//; s/-+$//'
}

while IFS=$'\t' read -r run device_name platform serial scenario app_id adb android_shim xcrun ios_shim; do
  safe_name="$(slugify "$device_name")"
  if [[ -z "$safe_name" ]]; then
    safe_name="device"
  fi
  trace_dir="$TRACE_ROOT/$safe_name-run-$run"
  mkdir -p "$trace_dir"

  zmr_args=(run "$scenario" --platform "$platform" --device "$serial" --trace-dir "$trace_dir")
  if [[ -n "$app_id" ]]; then
    zmr_args+=(--app-id "$app_id")
  fi
  if [[ -n "$adb" ]]; then
    zmr_args+=(--adb "$adb")
  fi
  if [[ -n "$android_shim" ]]; then
    zmr_args+=(--android-shim "$android_shim")
  fi
  if [[ -n "$xcrun" ]]; then
    zmr_args+=(--xcrun "$xcrun")
  fi
  if [[ -n "$ios_shim" ]]; then
    zmr_args+=(--ios-shim "$ios_shim")
  fi

  command_status=0
  start_ms="$(python3 -c 'import time; print(int(time.time() * 1000))')"
  "$ZMR_BIN" "${zmr_args[@]}" || command_status=$?
  end_ms="$(python3 -c 'import time; print(int(time.time() * 1000))')"
  duration_ms=$((end_ms - start_ms))

  row="$("$ROOT/scripts/benchmark_result_row.py" \
    --tool zmr \
    --run "$run" \
    --command-status "$command_status" \
    --duration-ms "$duration_ms" \
    --trace-dir "$trace_dir")"
  python3 - "$row" "$device_name" "$platform" "$serial" "$scenario" <<'PY' >> "$RESULTS"
import json
import sys

row = json.loads(sys.argv[1])
row["deviceName"] = sys.argv[2]
row["platform"] = sys.argv[3]
row["serial"] = sys.argv[4]
row["scenario"] = sys.argv[5]
print(json.dumps(row, separators=(",", ":")))
PY
done < "$ROWS"

python3 - "$RESULTS" "$SUMMARY" <<'PY'
import json
import statistics
import sys

results_path = sys.argv[1]
summary_path = sys.argv[2]
rows = []
with open(results_path, "r", encoding="utf-8") as fh:
    rows = [json.loads(line) for line in fh if line.strip()]

total = len(rows)
failed = sum(1 for row in rows if row.get("status") != "ok" or row.get("traceStatus") == "failed")
passed = total - failed
durations = [int(row.get("durationMs", 0)) for row in rows]
pass_rate = (passed / total * 100.0) if total else 0.0
summary = {
    "totalRuns": total,
    "passed": passed,
    "failed": failed,
    "passRate": round(pass_rate, 2),
    "meanMs": round(statistics.mean(durations), 2) if durations else 0,
    "resultsPath": "matrix.jsonl",
}
with open(summary_path, "w", encoding="utf-8") as fh:
    json.dump(summary, fh, separators=(",", ":"))
    fh.write("\n")
print(f"matrix: runs={total} passRate={pass_rate:.2f}% failures={failed}")
PY

gate_failed=0
python3 - "$SUMMARY" "$MIN_PASS_RATE" "$MAX_FAILURES" <<'PY' || gate_failed=$?
import json
import sys

summary_path, min_pass_rate, max_failures = sys.argv[1:4]
with open(summary_path, "r", encoding="utf-8") as fh:
    summary = json.load(fh)

failed = False
if min_pass_rate and summary["passRate"] < float(min_pass_rate):
    print(f"matrix gate failed: passRate={summary['passRate']:.2f}% < {float(min_pass_rate):.2f}%")
    failed = True
if max_failures and summary["failed"] > int(max_failures):
    print(f"matrix gate failed: failures={summary['failed']} > {int(max_failures)}")
    failed = True
raise SystemExit(1 if failed else 0)
PY

if [[ "$gate_failed" -ne 0 ]]; then
  exit "$gate_failed"
fi
