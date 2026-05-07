#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZMR_BIN="${ZMR_BIN:-$(command -v zmr 2>/dev/null || printf '%s' "$ROOT/zig-out/bin/zmr")}"
RUNS="${RUNS:-5}"
DEVICE="${DEVICE:-}"
TRACE_ROOT="${TRACE_ROOT:-$ROOT/traces/bench-$(date +%Y%m%d-%H%M%S)}"
RESULTS="$TRACE_ROOT/results.jsonl"
ZMR_SCENARIO=""
PLATFORM="${PLATFORM:-}"
APP_ID="${APP_ID:-}"
ADB="${ADB:-}"
ANDROID_SHIM="${ANDROID_SHIM:-}"
XCRUN="${XCRUN:-}"
IOS_SHIM="${IOS_SHIM:-}"
MIN_PASS_RATE="${MIN_PASS_RATE:-}"
MAX_FAILURES="${MAX_FAILURES:-}"
MAX_MEAN_MS="${MAX_MEAN_MS:-}"
MAX_P95_MS="${MAX_P95_MS:-}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/benchmark.sh --zmr <scenario.json> --device <serial> [--runs 10] [--trace-root <dir>] [gate options]

Gate options:
  --min-pass-rate <pct>  Minimum pass rate percentage, for example 100.
  --max-failures <n>     Maximum allowed failed runs.
  --max-mean-ms <ms>     Maximum allowed mean run duration.
  --max-p95-ms <ms>      Maximum allowed p95 run duration.

Forwarded ZMR options:
  --platform <android|ios>
  --app-id <id>
  --adb <path>
  --android-shim <path>
  --xcrun <path>
  --ios-shim <path>

Environment:
  ZMR_BIN       Path to zmr binary. Defaults to ./zig-out/bin/zmr.
  RUNS          Default run count when --runs is omitted.
  DEVICE        Default Android serial when --device is omitted.
  TRACE_ROOT    Default benchmark output root.
  PLATFORM, APP_ID, ADB, ANDROID_SHIM, XCRUN, IOS_SHIM
                Default forwarded ZMR options when matching flags are omitted.
  MIN_PASS_RATE, MAX_FAILURES, MAX_MEAN_MS, MAX_P95_MS
                Default gate thresholds when matching flags are omitted.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --zmr)
      ZMR_SCENARIO="${2:-}"
      shift 2
      ;;
    --device)
      DEVICE="${2:-}"
      shift 2
      ;;
    --runs)
      RUNS="${2:-}"
      shift 2
      ;;
    --trace-root)
      TRACE_ROOT="${2:-}"
      RESULTS="$TRACE_ROOT/results.jsonl"
      shift 2
      ;;
    --platform)
      PLATFORM="${2:-}"
      shift 2
      ;;
    --app-id)
      APP_ID="${2:-}"
      shift 2
      ;;
    --adb)
      ADB="${2:-}"
      shift 2
      ;;
    --android-shim)
      ANDROID_SHIM="${2:-}"
      shift 2
      ;;
    --xcrun)
      XCRUN="${2:-}"
      shift 2
      ;;
    --ios-shim)
      IOS_SHIM="${2:-}"
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
    --max-mean-ms)
      MAX_MEAN_MS="${2:-}"
      shift 2
      ;;
    --max-p95-ms)
      MAX_P95_MS="${2:-}"
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

if [[ -z "$ZMR_SCENARIO" ]]; then
  echo "--zmr is required" >&2
  usage >&2
  exit 2
fi

if [[ -z "$DEVICE" ]]; then
  echo "--device or DEVICE is required" >&2
  usage >&2
  exit 2
fi

if [[ ! "$RUNS" =~ ^[0-9]+$ || "$RUNS" -lt 1 ]]; then
  echo "--runs must be a positive integer" >&2
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
validate_optional_integer "--max-mean-ms" "$MAX_MEAN_MS"
validate_optional_integer "--max-p95-ms" "$MAX_P95_MS"

mkdir -p "$TRACE_ROOT"
: > "$RESULTS"

run_one() {
  local tool="$1"
  local run="$2"
  local command_status=0
  local start_ms end_ms duration_ms trace_dir
  local -a zmr_args=()

  trace_dir="$TRACE_ROOT/$tool-$run"
  mkdir -p "$trace_dir"
  if [[ -n "$PLATFORM" ]]; then
    zmr_args+=(--platform "$PLATFORM")
  fi
  if [[ -n "$APP_ID" ]]; then
    zmr_args+=(--app-id "$APP_ID")
  fi
  if [[ -n "$ADB" ]]; then
    zmr_args+=(--adb "$ADB")
  fi
  if [[ -n "$ANDROID_SHIM" ]]; then
    zmr_args+=(--android-shim "$ANDROID_SHIM")
  fi
  if [[ -n "$XCRUN" ]]; then
    zmr_args+=(--xcrun "$XCRUN")
  fi
  if [[ -n "$IOS_SHIM" ]]; then
    zmr_args+=(--ios-shim "$IOS_SHIM")
  fi
  start_ms="$(python3 -c 'import time; print(int(time.time() * 1000))')"
  if [[ "${#zmr_args[@]}" -gt 0 ]]; then
    "$ZMR_BIN" run "$ZMR_SCENARIO" --device "$DEVICE" "${zmr_args[@]}" --trace-dir "$trace_dir" || command_status=$?
  else
    "$ZMR_BIN" run "$ZMR_SCENARIO" --device "$DEVICE" --trace-dir "$trace_dir" || command_status=$?
  fi

  end_ms="$(python3 -c 'import time; print(int(time.time() * 1000))')"
  duration_ms=$((end_ms - start_ms))

  "$ROOT/scripts/benchmark_result_row.py" \
    --tool "$tool" \
    --run "$run" \
    --command-status "$command_status" \
    --duration-ms "$duration_ms" \
    --trace-dir "$trace_dir" >> "$RESULTS"

  return "$command_status"
}

for run in $(seq 1 "$RUNS"); do
  run_one zmr "$run" || true
done

python3 - "$RESULTS" <<'PY'
import json
import math
import statistics
import sys
from collections import defaultdict

path = sys.argv[1]
rows = [json.loads(line) for line in open(path, encoding="utf-8") if line.strip()]
by_tool = defaultdict(list)
for row in rows:
    by_tool[row["tool"]].append(row)

for tool, items in sorted(by_tool.items()):
    durations = [item["durationMs"] for item in items]
    failures = sum(1 for item in items if item["status"] != "ok")
    mean = round(statistics.mean(durations)) if durations else 0
    p95 = sorted(durations)[max(0, math.ceil(len(durations) * 0.95) - 1)] if durations else 0
    print(f"{tool}: runs={len(items)} failures={failures} meanMs={mean} p95Ms={p95}")

print(f"results={path}")
PY

gate_args=()
if [[ -n "$MIN_PASS_RATE" ]]; then
  gate_args+=(--min-pass-rate "$MIN_PASS_RATE")
fi
if [[ -n "$MAX_FAILURES" ]]; then
  gate_args+=(--max-failures "$MAX_FAILURES")
fi
if [[ -n "$MAX_MEAN_MS" ]]; then
  gate_args+=(--max-mean-ms "$MAX_MEAN_MS")
fi
if [[ -n "$MAX_P95_MS" ]]; then
  gate_args+=(--max-p95-ms "$MAX_P95_MS")
fi

if [[ "${#gate_args[@]}" -gt 0 ]]; then
  "$ROOT/scripts/benchmark_gate.py" --results "$RESULTS" "${gate_args[@]}"
fi
