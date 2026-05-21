#!/usr/bin/env bash
set -euo pipefail

SOURCE="${BASH_SOURCE[0]}"
while [[ -h "$SOURCE" ]]; do
  SOURCE_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  if [[ "$SOURCE" != /* ]]; then
    SOURCE="$SOURCE_DIR/$SOURCE"
  fi
done

ROOT="$(cd -P "$(dirname "$SOURCE")/.." && pwd)"
CALLER_CWD="$(pwd -P)"

# Some sandboxed environments do not allow writing to the default temp directory
# (/var/folders, /tmp). Use a repo-local TMPDIR so adb/xcrun/mktemp/heredocs work.
if [[ -z "${TMPDIR:-}" || ! -w "${TMPDIR:-/nonexistent}" ]]; then
  TMPDIR="$ROOT/traces/tmp"
  mkdir -p "$TMPDIR"
  export TMPDIR
fi

ZMR_BIN="${ZMR_BIN:-$(command -v zmr 2>/dev/null || printf '%s' "$ROOT/zig-out/bin/zmr")}"
RUNS="${RUNS:-5}"
DEVICE="${DEVICE:-}"
TRACE_ROOT="${TRACE_ROOT:-$CALLER_CWD/traces/bench-$(date +%Y%m%d-%H%M%S)}"
RESULTS=""
RESULTS_EXPLICIT=0
REPLACE=0
ZMR_SCENARIO=""
PLATFORM="${PLATFORM:-}"
APP_ID="${APP_ID:-}"
ADB="${ADB:-}"
ANDROID_SHIM="${ANDROID_SHIM:-}"
XCRUN="${XCRUN:-}"
IOS_SHIM="${IOS_SHIM:-}"
IOS_DEVICE_TYPE="${IOS_DEVICE_TYPE:-}"
APP_BUILD="${APP_BUILD:-}"
MIN_PASS_RATE="${MIN_PASS_RATE:-}"
MAX_FAILURES="${MAX_FAILURES:-}"
MAX_MEAN_MS="${MAX_MEAN_MS:-}"
MAX_P95_MS="${MAX_P95_MS:-}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/benchmark.sh --zmr <scenario.json> --device <serial> [--runs 10] [--trace-root <dir>] [--results <path>] [gate options]

Gate options:
  --min-pass-rate <pct>  Minimum pass rate percentage, for example 100.
  --max-failures <n>     Maximum allowed failed runs.
  --max-mean-ms <ms>     Maximum allowed mean run duration.
  --max-p95-ms <ms>      Maximum allowed p95 run duration.

Output options:
  --results <path>       Results JSONL path. Defaults to <trace-root>/results.jsonl.
                         Explicit results paths are appended by default.
  --replace              Truncate --results before writing.

Forwarded ZMR options:
  --platform <android|ios>
  --app-id <id>
  --adb <path>
  --android-shim <path>
  --xcrun <path>
  --ios-shim <path>
  --ios-device-type <simulator|physical>
  --app-build <id>       App build fingerprint, artifact path, or CI build id for comparison context.

Environment:
  ZMR_BIN       Path to zmr binary. Defaults to ./zig-out/bin/zmr.
  RUNS          Default run count when --runs is omitted.
  DEVICE        Default Android serial when --device is omitted.
  TRACE_ROOT    Default benchmark output root. Otherwise traces/bench-<timestamp> in the caller directory.
  PLATFORM, APP_ID, ADB, ANDROID_SHIM, XCRUN, IOS_SHIM, IOS_DEVICE_TYPE, APP_BUILD
                Default forwarded ZMR options when matching flags are omitted.
  MIN_PASS_RATE, MAX_FAILURES, MAX_MEAN_MS, MAX_P95_MS
                Default gate thresholds when matching flags are omitted.
USAGE
}

die() {
  echo "error: $*" >&2
  exit 2
}

require_value() {
  local flag="$1"
  local value="${2-}"
  if [[ -z "$value" || "$value" == --* ]]; then
    die "$flag requires a value"
  fi
  printf '%s\n' "$value"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --zmr)
      ZMR_SCENARIO="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --device)
      DEVICE="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --runs)
      RUNS="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --trace-root)
      TRACE_ROOT="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --results)
      RESULTS="$(require_value "$1" "${2-}")"
      RESULTS_EXPLICIT=1
      shift 2
      ;;
    --replace)
      REPLACE=1
      shift
      ;;
    --platform)
      PLATFORM="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --app-id)
      APP_ID="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --adb)
      ADB="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --android-shim)
      ANDROID_SHIM="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --xcrun)
      XCRUN="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --ios-shim)
      IOS_SHIM="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --ios-device-type)
      IOS_DEVICE_TYPE="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --app-build)
      APP_BUILD="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --min-pass-rate)
      MIN_PASS_RATE="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --max-failures)
      MAX_FAILURES="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --max-mean-ms)
      MAX_MEAN_MS="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --max-p95-ms)
      MAX_P95_MS="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

if [[ -z "$ZMR_SCENARIO" ]]; then
  echo "error: --zmr is required" >&2
  usage >&2
  exit 2
fi

if [[ -z "$DEVICE" ]]; then
  echo "error: --device or DEVICE is required" >&2
  usage >&2
  exit 2
fi

if [[ ! "$RUNS" =~ ^[0-9]+$ || "$RUNS" -lt 1 ]]; then
  die "--runs must be a positive integer"
fi

if [[ ! -x "$ZMR_BIN" ]]; then
  die "zmr binary is not executable: $ZMR_BIN"
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
if [[ -n "$IOS_DEVICE_TYPE" && "$IOS_DEVICE_TYPE" != "simulator" && "$IOS_DEVICE_TYPE" != "physical" ]]; then
  echo "--ios-device-type must be simulator or physical" >&2
  exit 2
fi

mkdir -p "$TRACE_ROOT"
if [[ -z "$RESULTS" ]]; then
  RESULTS="$TRACE_ROOT/results.jsonl"
fi
mkdir -p "$(dirname "$RESULTS")"
if [[ "$REPLACE" -eq 1 || "$RESULTS_EXPLICIT" -eq 0 ]]; then
  : > "$RESULTS"
else
  touch "$RESULTS"
fi

run_one() {
  local tool="$1"
  local run="$2"
  local command_status=0
  local start_ms end_ms duration_ms trace_dir
  local -a zmr_args=()
  local -a metadata_args=()

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
  if [[ -n "$IOS_DEVICE_TYPE" ]]; then
    zmr_args+=(--ios-device-type "$IOS_DEVICE_TYPE")
  fi
  if [[ -n "$PLATFORM" ]]; then
    metadata_args+=(--platform "$PLATFORM")
  fi
  if [[ -n "$DEVICE" ]]; then
    metadata_args+=(--device "$DEVICE")
  fi
  if [[ -n "$APP_ID" ]]; then
    metadata_args+=(--app-id "$APP_ID")
  fi
  if [[ -n "$ZMR_SCENARIO" ]]; then
    metadata_args+=(--scenario "$ZMR_SCENARIO")
  fi
  if [[ -n "$APP_BUILD" ]]; then
    metadata_args+=(--app-build "$APP_BUILD")
  fi
  start_ms="$(python3 -c 'import time; print(int(time.time() * 1000))')"
  if [[ "${#zmr_args[@]}" -gt 0 ]]; then
    "$ZMR_BIN" run "$ZMR_SCENARIO" --device "$DEVICE" "${zmr_args[@]}" --trace-dir "$trace_dir" || command_status=$?
  else
    "$ZMR_BIN" run "$ZMR_SCENARIO" --device "$DEVICE" --trace-dir "$trace_dir" || command_status=$?
  fi

  end_ms="$(python3 -c 'import time; print(int(time.time() * 1000))')"
  duration_ms=$((end_ms - start_ms))

  if [[ "${#metadata_args[@]}" -gt 0 ]]; then
    "$ROOT/scripts/benchmark_result_row.py" \
      --tool "$tool" \
      --run "$run" \
      --command-status "$command_status" \
      --duration-ms "$duration_ms" \
      --trace-dir "$trace_dir" \
      "${metadata_args[@]}" >> "$RESULTS"
  else
    "$ROOT/scripts/benchmark_result_row.py" \
      --tool "$tool" \
      --run "$run" \
      --command-status "$command_status" \
      --duration-ms "$duration_ms" \
      --trace-dir "$trace_dir" >> "$RESULTS"
  fi

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
