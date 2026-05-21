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

TOOL="${TOOL:-baseline}"
RUNS="${RUNS:-5}"
TRACE_ROOT="${TRACE_ROOT:-$CALLER_CWD/traces/bench-command-$(date +%Y%m%d-%H%M%S)}"
RESULTS=""
CWD=""
REPLACE=0
PLATFORM="${PLATFORM:-}"
DEVICE="${DEVICE:-}"
APP_ID="${APP_ID:-}"
SCENARIO="${SCENARIO:-}"
APP_BUILD="${APP_BUILD:-}"
MIN_PASS_RATE="${MIN_PASS_RATE:-}"
MAX_FAILURES="${MAX_FAILURES:-}"
MAX_MEAN_MS="${MAX_MEAN_MS:-}"
MAX_P95_MS="${MAX_P95_MS:-}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/benchmark-command.sh --tool <label> [options] -- <command> [args...]

Runs any local command repeatedly and appends normalized benchmark rows that can
be compared with ZMR rows through zmr-compare-benchmarks.

Options:
  --tool <label>        Baseline tool label, for example runner-a or runner-b.
  --runs <n>            Number of command runs. Default: 5.
  --trace-root <dir>    Directory for stdout/stderr logs. Default: traces/bench-command-<timestamp> in the caller directory.
  --results <path>      Results JSONL path. Defaults to <trace-root>/results.jsonl.
                        Explicit results paths are appended by default.
  --replace             Truncate --results before writing.
  --cwd <dir>           Run the command from this working directory.
  --platform <name>     Platform context, for example android or ios.
  --device <id>         Device context shared with candidate rows.
  --app-id <id>         App id/bundle id context shared with candidate rows.
  --scenario <path>     Scenario or flow identifier used by this command.
  --app-build <id>      App build fingerprint, artifact path, or CI build id.
  --min-pass-rate <pct> Optional gate minimum.
  --max-failures <n>    Optional gate maximum.
  --max-mean-ms <ms>    Optional mean duration maximum.
  --max-p95-ms <ms>     Optional p95 duration maximum.
  -h, --help            Show this help.

Example:
  zmr-benchmark-command \
    --tool runner-a \
    --runs 20 \
    --trace-root traces/runner-a-login \
    --results traces/comparison/results.jsonl \
    -- runner-a test .runner-a/login.yaml
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

quote_cmd() {
  local quoted=()
  local arg
  for arg in "$@"; do
    quoted+=("$(printf '%q' "$arg")")
  done
  printf '%s\n' "${quoted[*]}"
}

RESULTS_EXPLICIT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tool)
      TOOL="$(require_value "$1" "${2-}")"
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
    --cwd)
      CWD="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --platform)
      PLATFORM="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --device)
      DEVICE="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --app-id)
      APP_ID="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --scenario)
      SCENARIO="$(require_value "$1" "${2-}")"
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
    --)
      shift
      break
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument before --: $1"
      ;;
  esac
done

[[ -n "$TOOL" ]] || die "--tool cannot be empty"
[[ "$RUNS" =~ ^[0-9]+$ && "$RUNS" -ge 1 ]] || die "--runs must be a positive integer"
[[ $# -gt 0 ]] || die "command is required after --"
if [[ -n "$CWD" && ! -d "$CWD" ]]; then
  die "--cwd directory not found: $CWD"
fi

validate_optional_number() {
  local name="$1"
  local value="$2"
  if [[ -n "$value" && ! "$value" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    die "$name must be a non-negative number"
  fi
}

validate_optional_integer() {
  local name="$1"
  local value="$2"
  if [[ -n "$value" && ! "$value" =~ ^[0-9]+$ ]]; then
    die "$name must be a non-negative integer"
  fi
}

validate_optional_number "--min-pass-rate" "$MIN_PASS_RATE"
validate_optional_integer "--max-failures" "$MAX_FAILURES"
validate_optional_integer "--max-mean-ms" "$MAX_MEAN_MS"
validate_optional_integer "--max-p95-ms" "$MAX_P95_MS"

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

COMMAND=("$@")
metadata_args=()
if [[ -n "$PLATFORM" ]]; then
  metadata_args+=(--platform "$PLATFORM")
fi
if [[ -n "$DEVICE" ]]; then
  metadata_args+=(--device "$DEVICE")
fi
if [[ -n "$APP_ID" ]]; then
  metadata_args+=(--app-id "$APP_ID")
fi
if [[ -n "$SCENARIO" ]]; then
  metadata_args+=(--scenario "$SCENARIO")
fi
if [[ -n "$APP_BUILD" ]]; then
  metadata_args+=(--app-build "$APP_BUILD")
fi
echo "Benchmark command output: $TRACE_ROOT"
echo "Results: $RESULTS"
echo "Tool: $TOOL"
echo "+ $(quote_cmd "${COMMAND[@]}")"

for run in $(seq 1 "$RUNS"); do
  run_dir="$TRACE_ROOT/$TOOL-$run"
  mkdir -p "$run_dir"
  printf '%s\n' "$(quote_cmd "${COMMAND[@]}")" > "$run_dir/command.txt"

  command_status=0
  start_ms="$(python3 -c 'import time; print(int(time.time() * 1000))')"
  if [[ -n "$CWD" ]]; then
    (cd "$CWD" && "${COMMAND[@]}") > "$run_dir/stdout.log" 2> "$run_dir/stderr.log" || command_status=$?
  else
    "${COMMAND[@]}" > "$run_dir/stdout.log" 2> "$run_dir/stderr.log" || command_status=$?
  fi
  end_ms="$(python3 -c 'import time; print(int(time.time() * 1000))')"
  duration_ms=$((end_ms - start_ms))

  if [[ "${#metadata_args[@]}" -gt 0 ]]; then
    "$ROOT/scripts/benchmark_result_row.py" \
      --tool "$TOOL" \
      --run "$run" \
      --command-status "$command_status" \
      --duration-ms "$duration_ms" \
      --trace-dir "$run_dir" \
      "${metadata_args[@]}" >> "$RESULTS"
  else
    "$ROOT/scripts/benchmark_result_row.py" \
      --tool "$TOOL" \
      --run "$run" \
      --command-status "$command_status" \
      --duration-ms "$duration_ms" \
      --trace-dir "$run_dir" >> "$RESULTS"
  fi
done

python3 - "$RESULTS" "$TOOL" <<'PY'
import json
import math
import statistics
import sys

path, tool = sys.argv[1], sys.argv[2]
rows = [
    json.loads(line)
    for line in open(path, encoding="utf-8")
    if line.strip() and json.loads(line).get("tool") == tool
]
durations = [int(row.get("durationMs", 0)) for row in rows]
failures = sum(1 for row in rows if row.get("status") != "ok")
mean = round(statistics.mean(durations)) if durations else 0
p95 = sorted(durations)[max(0, math.ceil(len(durations) * 0.95) - 1)] if durations else 0
print(f"{tool}: runs={len(rows)} failures={failures} meanMs={mean} p95Ms={p95}")
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
