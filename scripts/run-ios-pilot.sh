#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_ROOT="${APP_ROOT:-}"
APP_PATH="${APP_PATH:-}"
DEVICE="${DEVICE:-booted}"
TRACE_ROOT="${TRACE_ROOT:-$ROOT/traces/ios-app-pilot-$(date +%Y%m%d-%H%M%S)}"
ZMR_BIN="${ZMR_BIN:-$ROOT/zig-out/bin/zmr}"
XCRUN="${XCRUN:-xcrun}"
APP_ID="${APP_ID:-com.example.mobiletest}"
IOS_SHIM="${IOS_SHIM:-}"
RUNS="${RUNS:-1}"
MIN_PASS_RATE="${MIN_PASS_RATE:-100}"
MAX_FAILURES="${MAX_FAILURES:-0}"
MAX_MEAN_MS="${MAX_MEAN_MS:-}"
MAX_P95_MS="${MAX_P95_MS:-}"
DRY_RUN=0

usage() {
  cat <<'USAGE'
Usage:
  scripts/run-ios-pilot.sh --app-path <Sample.app> [options]

Runs a configurable iOS simulator smoke pilot:
  1. build/validate zmr
  2. install a simulator .app
  3. launch/open a deep link through examples/ios-smoke.json
  4. capture screenshot/log snapshot artifacts
  5. generate report and normal/redacted .zmrtrace bundles

Options:
  --app-root <dir>     Optional app repo root, used only for output context.
  --app-path <path>    Built .app for an iOS simulator. Required.
  --device <udid>      Simulator UDID. Default: booted.
  --app-id <bundle>    Bundle id. Default: com.example.mobiletest.
  --trace-root <dir>   Output directory. Default: traces/ios-app-pilot-<timestamp>.
  --zmr-bin <path>     zmr binary. Default: zig-out/bin/zmr.
  --xcrun <path>       xcrun path. Default: xcrun.
  --ios-shim <path>    Optional XCTest shim command for selector hierarchy/actions.
  --runs <n>           Run each flow n times. n=1 writes trace bundles; n>1 writes benchmark reports.
  --min-pass-rate <pct>
                       Repeated-run gate minimum. Default: 100.
  --max-failures <n>   Repeated-run gate maximum. Default: 0.
  --max-mean-ms <ms>   Optional repeated-run mean duration maximum.
  --max-p95-ms <ms>    Optional repeated-run p95 duration maximum.
  --dry-run            Print commands without executing them.
  -h, --help           Show this help.

Notes:
  Without --ios-shim, iOS V1 is a simulator smoke path: install, launch,
  deep link, screenshot, logs, and trace export. With --ios-shim, ZMR also
  uses the shim for hierarchy and selector-grade actions.
USAGE
}

die() {
  echo "error: $*" >&2
  exit 2
}

quote_cmd() {
  local quoted=()
  local arg
  for arg in "$@"; do
    quoted+=("$(printf '%q' "$arg")")
  done
  printf '%s\n' "${quoted[*]}"
}

run() {
  echo "+ $(quote_cmd "$@")"
  if [[ "$DRY_RUN" -eq 0 ]]; then
    "$@"
  fi
}

is_retryable_simctl_text() {
  local text="$1"
  [[ "$text" == *"CoreSimulatorService connection became invalid"* ]] ||
    [[ "$text" == *"Failed to initialize simulator device set"* ]] ||
    [[ "$text" == *"simdiskimaged"* ]] ||
    [[ "$text" == *"Connection refused"* ]]
}

run_simctl_install() {
  echo "+ $(quote_cmd "$XCRUN" simctl install "$DEVICE" "$APP_PATH")"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    return 0
  fi

  local attempt status err_file err_text
  err_file="$(mktemp)"
  for attempt in 1 2 3 4 5 6; do
    : > "$err_file"
    set +e
    "$XCRUN" simctl install "$DEVICE" "$APP_PATH" 2>"$err_file"
    status=$?
    set -e
    if [[ "$status" -eq 0 ]]; then
      rm -f "$err_file"
      return 0
    fi
    err_text="$(cat "$err_file")"
    if [[ "$attempt" == "6" ]] || ! is_retryable_simctl_text "$err_text"; then
      cat "$err_file" >&2
      rm -f "$err_file"
      return "$status"
    fi
    echo "warning: simctl install hit a transient CoreSimulator error; retrying ($attempt/6)" >&2
    sleep 0.5
  done
}

preflight_ios_device() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    return 0
  fi

  local devices_json
  devices_json="$("$ZMR_BIN" devices --json --platform ios --xcrun "$XCRUN" 2>/dev/null || true)"
  if [[ "$DEVICE" == "booted" ]]; then
    if [[ "$devices_json" == *'"count":0'* || -z "$devices_json" ]]; then
      if simctl_has_booted_device ""; then
        return 0
      fi
      if [[ -z "$devices_json" ]]; then
        echo "warning: could not verify booted iOS simulator during preflight; continuing to simctl install" >&2
        return 0
      fi
      echo "error: no booted iOS simulator found" >&2
      echo "errorCode: setup.ios.no_booted_simulators" >&2
      echo "hint: boot a simulator, then run zmr doctor --json --xcrun $(printf '%q' "$XCRUN")." >&2
      "$ZMR_BIN" doctor --json --xcrun "$XCRUN" >&2 || true
      exit 2
    fi
    return 0
  fi

  if [[ "$devices_json" != *'"serial":"'"$DEVICE"'"'* ]]; then
    if simctl_has_booted_device "$DEVICE"; then
      return 0
    fi
    if [[ -z "$devices_json" ]]; then
      echo "warning: could not verify iOS simulator during preflight; continuing to simctl install" >&2
      return 0
    fi
    echo "error: iOS simulator not found or not booted: $DEVICE" >&2
    echo "errorCode: setup.ios.no_booted_simulators" >&2
    echo "hint: boot the requested simulator, then run zmr doctor --json --xcrun $(printf '%q' "$XCRUN")." >&2
    "$ZMR_BIN" doctor --json --xcrun "$XCRUN" >&2 || true
    exit 2
  fi
}

simctl_has_booted_device() {
  local wanted="${1:-}"
  local booted_text
  local attempt
  for attempt in 1 2 3 4 5 6; do
    booted_text="$("$XCRUN" simctl list devices booted 2>/dev/null || true)"
    if [[ -n "$booted_text" ]]; then
      if [[ -z "$wanted" && "$booted_text" == *"(Booted)"* ]]; then
        return 0
      fi
      if [[ -n "$wanted" && "$booted_text" == *"$wanted"* && "$booted_text" == *"(Booted)"* ]]; then
        return 0
      fi
    fi
    sleep 0.5
  done
  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-root)
      APP_ROOT="${2:-}"
      shift 2
      ;;
    --app-path)
      APP_PATH="${2:-}"
      shift 2
      ;;
    --device)
      DEVICE="${2:-}"
      shift 2
      ;;
    --app-id)
      APP_ID="${2:-}"
      shift 2
      ;;
    --trace-root)
      TRACE_ROOT="${2:-}"
      shift 2
      ;;
    --zmr-bin)
      ZMR_BIN="${2:-}"
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
    --runs)
      RUNS="${2:-}"
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
    --dry-run)
      DRY_RUN=1
      shift
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

[[ -n "$APP_PATH" ]] || die "--app-path is required"
[[ "$RUNS" =~ ^[0-9]+$ && "$RUNS" -ge 1 ]] || die "--runs must be a positive integer"
[[ "$MIN_PASS_RATE" =~ ^[0-9]+([.][0-9]+)?$ ]] || die "--min-pass-rate must be a non-negative number"
[[ "$MAX_FAILURES" =~ ^[0-9]+$ ]] || die "--max-failures must be a non-negative integer"
[[ -z "$MAX_MEAN_MS" || "$MAX_MEAN_MS" =~ ^[0-9]+$ ]] || die "--max-mean-ms must be a non-negative integer"
[[ -z "$MAX_P95_MS" || "$MAX_P95_MS" =~ ^[0-9]+$ ]] || die "--max-p95-ms must be a non-negative integer"
if [[ "$DRY_RUN" -eq 0 ]]; then
  [[ -d "$APP_PATH" ]] || die "iOS simulator app not found: $APP_PATH"
  if [[ -n "$APP_ROOT" ]]; then
    [[ -d "$APP_ROOT" ]] || die "app repo not found: $APP_ROOT"
  fi
fi

echo "iOS pilot output: $TRACE_ROOT"
if [[ -n "$APP_ROOT" ]]; then
  echo "App root: $APP_ROOT"
fi
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "DRY RUN: commands will be printed but not executed"
fi

run mkdir -p "$TRACE_ROOT" "$ROOT/zig-out/bin"

if [[ ! -x "$ZMR_BIN" ]]; then
  target_args=()
  if [[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "arm64" ]]; then
    target_args=(-target aarch64-macos.15.0)
  fi
  run zig build-exe src/main.zig "${target_args[@]}" -O Debug -femit-bin="$ZMR_BIN"
fi

run "$ZMR_BIN" version
run "$ZMR_BIN" validate examples/ios-smoke.json
if [[ -n "$IOS_SHIM" ]]; then
  run "$ZMR_BIN" validate examples/ios-shim-smoke.json
fi
preflight_ios_device
run_simctl_install

if [[ "$RUNS" -eq 1 ]]; then
  TRACE_DIR="$TRACE_ROOT/ios-smoke"
  run rm -rf "$TRACE_DIR"
  if [[ -n "$IOS_SHIM" ]]; then
    run "$ZMR_BIN" run examples/ios-smoke.json --platform ios --device "$DEVICE" --app-id "$APP_ID" --xcrun "$XCRUN" --ios-shim "$IOS_SHIM" --trace-dir "$TRACE_DIR"
  else
    run "$ZMR_BIN" run examples/ios-smoke.json --platform ios --device "$DEVICE" --app-id "$APP_ID" --xcrun "$XCRUN" --trace-dir "$TRACE_DIR"
  fi
  run "$ZMR_BIN" report "$TRACE_DIR" --out "$TRACE_DIR/report.html"
  run "$ZMR_BIN" export "$TRACE_DIR" --out "$TRACE_ROOT/ios-smoke.zmrtrace"
  run "$ZMR_BIN" export "$TRACE_DIR" --out "$TRACE_ROOT/ios-smoke-redacted.zmrtrace" --redact

  if [[ -n "$IOS_SHIM" ]]; then
    SHIM_TRACE_DIR="$TRACE_ROOT/ios-shim-smoke"
    run rm -rf "$SHIM_TRACE_DIR"
    run "$ZMR_BIN" run examples/ios-shim-smoke.json --platform ios --device "$DEVICE" --app-id "$APP_ID" --xcrun "$XCRUN" --ios-shim "$IOS_SHIM" --trace-dir "$SHIM_TRACE_DIR"
    run "$ZMR_BIN" report "$SHIM_TRACE_DIR" --out "$SHIM_TRACE_DIR/report.html"
    run "$ZMR_BIN" export "$SHIM_TRACE_DIR" --out "$TRACE_ROOT/ios-shim-smoke.zmrtrace"
    run "$ZMR_BIN" export "$SHIM_TRACE_DIR" --out "$TRACE_ROOT/ios-shim-smoke-redacted.zmrtrace" --redact
  fi
else
  benchmark_gate_args=(--min-pass-rate "$MIN_PASS_RATE" --max-failures "$MAX_FAILURES")
  if [[ -n "$MAX_MEAN_MS" ]]; then
    benchmark_gate_args+=(--max-mean-ms "$MAX_MEAN_MS")
  fi
  if [[ -n "$MAX_P95_MS" ]]; then
    benchmark_gate_args+=(--max-p95-ms "$MAX_P95_MS")
  fi

  if [[ -n "$IOS_SHIM" ]]; then
    ZMR_BIN="$ZMR_BIN" run "$ROOT/scripts/benchmark.sh" --zmr examples/ios-smoke.json --device "$DEVICE" --platform ios --app-id "$APP_ID" --xcrun "$XCRUN" --ios-shim "$IOS_SHIM" --runs "$RUNS" --trace-root "$TRACE_ROOT/ios-smoke-benchmark" "${benchmark_gate_args[@]}"
  else
    ZMR_BIN="$ZMR_BIN" run "$ROOT/scripts/benchmark.sh" --zmr examples/ios-smoke.json --device "$DEVICE" --platform ios --app-id "$APP_ID" --xcrun "$XCRUN" --runs "$RUNS" --trace-root "$TRACE_ROOT/ios-smoke-benchmark" "${benchmark_gate_args[@]}"
  fi
  run "$ZMR_BIN" report "$TRACE_ROOT/ios-smoke-benchmark" --out "$TRACE_ROOT/ios-smoke-benchmark/report.html"

  if [[ -n "$IOS_SHIM" ]]; then
    ZMR_BIN="$ZMR_BIN" run "$ROOT/scripts/benchmark.sh" --zmr examples/ios-shim-smoke.json --device "$DEVICE" --platform ios --app-id "$APP_ID" --xcrun "$XCRUN" --ios-shim "$IOS_SHIM" --runs "$RUNS" --trace-root "$TRACE_ROOT/ios-shim-smoke-benchmark" "${benchmark_gate_args[@]}"
    run "$ZMR_BIN" report "$TRACE_ROOT/ios-shim-smoke-benchmark" --out "$TRACE_ROOT/ios-shim-smoke-benchmark/report.html"
  fi
fi

cat <<EOF

iOS pilot complete.
Output directory: $TRACE_ROOT
Shareable bundle:
  $TRACE_ROOT/ios-smoke-redacted.zmrtrace
  $([[ -n "$IOS_SHIM" ]] && printf '%s/ios-shim-smoke-redacted.zmrtrace' "$TRACE_ROOT")
Viewer:
  $ROOT/viewer/index.html
EOF
