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

SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CALLER_CWD="$(pwd -P)"

# Some sandboxed environments do not allow writing to the default temp directory
# (/var/folders, /tmp). Use a repo-local TMPDIR so adb/xcrun/mktemp/heredocs work.
if [[ -z "${TMPDIR:-}" || ! -w "${TMPDIR:-/nonexistent}" ]]; then
  TMPDIR="$ROOT/traces/tmp"
  mkdir -p "$TMPDIR"
  export TMPDIR
fi

ANDROID_SELECTED=0
IOS_SELECTED=0
ANDROID_APP_ROOT="${ANDROID_APP_ROOT:-}"
ANDROID_APP_ID="${ANDROID_APP_ID:-}"
ANDROID_DEVICE="${ANDROID_DEVICE:-emulator-5554}"
ANDROID_APK="${ANDROID_APK:-}"
ANDROID_SCENARIO="${ANDROID_SCENARIO:-}"
ANDROID_SKIP_EMULATOR=0
ANDROID_SKIP_METRO=0
ADB="${ADB:-}"
IOS_APP_ROOT="${IOS_APP_ROOT:-}"
IOS_APP_ID="${IOS_APP_ID:-}"
IOS_DEVICE="${IOS_DEVICE:-booted}"
IOS_DEVICE_TYPE="${IOS_DEVICE_TYPE:-simulator}"
IOS_APP_PATH="${IOS_APP_PATH:-}"
IOS_SHIM="${IOS_SHIM:-}"
XCRUN="${XCRUN:-}"
ZMR_BIN="${ZMR_BIN:-$(command -v zmr 2>/dev/null || true)}"
TRACE_ROOT="${TRACE_ROOT:-$CALLER_CWD/traces/pilot-gate-$(date +%Y%m%d-%H%M%S)}"
EVIDENCE_OUT="${EVIDENCE_OUT:-}"
RUNS="${RUNS:-20}"
MIN_PASS_RATE="${MIN_PASS_RATE:-100}"
MAX_FAILURES="${MAX_FAILURES:-0}"
MAX_MEAN_MS="${MAX_MEAN_MS:-}"
ANDROID_MAX_P95_MS="${ANDROID_MAX_P95_MS:-30000}"
IOS_MAX_P95_MS="${IOS_MAX_P95_MS:-45000}"
DRY_RUN=0

usage() {
  cat <<'USAGE'
Usage:
  scripts/pilot-gate.sh [--android] [--ios] [options]

Runs the external real-device release gate by delegating to the Android and iOS
pilot wrappers with repeated-run thresholds. If neither --android nor --ios is
passed, both platforms are selected.

Android options:
  --android-app-root <dir>  App repo root for the Android pilot. Required when Android is selected.
  --android-app-id <id>     Android application id. Defaults to the pilot wrapper default.
  --android-device <serial> Android serial. Default: emulator-5554.
  --android-apk <path>      APK path. Defaults to the pilot wrapper default.
  --android-scenario <path> ZMR scenario JSON to run for the Android pilot.
  --adb <path>              adb path forwarded to the Android pilot.
  --skip-emulator           Require/use an already booted Android device.
  --skip-metro              Do not start the app test server for Android.

iOS options:
  --ios-app-root <dir>      App repo root for iOS pilot evidence. Required when iOS is selected.
  --ios-app-path <path>     Built .app/.ipa. Required when iOS is selected.
  --ios-app-id <id>         iOS bundle id. Defaults to the pilot wrapper default.
  --ios-device <udid>       Simulator UDID or booted. Default: booted.
  --ios-device-type <simulator|physical>
                            iOS target type. Default: simulator.
  --ios-shim <path>         XCTest shim command for selector-grade iOS runs.
  --xcrun <path>            xcrun path forwarded to the iOS pilot.
  --zmr-bin <path>          zmr binary path forwarded to pilot wrappers.

Gate options:
  --trace-root <dir>        Output root. Default: traces/pilot-gate-<timestamp>.
  --evidence-out <path>     Optional JSONL evidence file for zmr-release-readiness.
  --runs <n>                Repeated run count. Default: 20.
  --min-pass-rate <pct>     Minimum pass rate. Default: 100.
  --max-failures <n>        Maximum failed runs. Default: 0.
  --max-mean-ms <ms>        Optional mean duration maximum for both platforms.
  --android-max-p95-ms <ms> Android p95 duration maximum. Default: 30000.
  --ios-max-p95-ms <ms>     iOS p95 duration maximum. Default: 45000.
  --dry-run                 Print commands without executing them.
  -h, --help                Show this help.

Environment defaults mirror the upper-case option names, for example
ANDROID_APP_ROOT, IOS_APP_PATH, ADB, XCRUN, ZMR_BIN, RUNS, TRACE_ROOT, and EVIDENCE_OUT.
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

resolve_path_from_cwd() {
  local value="$1"
  local absolute dir base probe suffix
  local resolved_root
  if [[ -z "$value" ]]; then
    printf '\n'
    return 0
  fi
  if [[ "$value" == /* ]]; then
    absolute="$value"
  else
    absolute="$CALLER_CWD/$value"
  fi
  if [[ -d "$absolute" ]]; then
    cd "$absolute" && pwd -P
    return 0
  fi
  if [[ -e "$absolute" ]]; then
    dir="$(dirname "$absolute")"
    base="$(basename "$absolute")"
    printf '%s/%s\n' "$(cd "$dir" && pwd -P)" "$base"
    return 0
  fi
  dir="$(dirname "$absolute")"
  base="$(basename "$absolute")"
  if [[ -d "$dir" ]]; then
    printf '%s/%s\n' "$(cd "$dir" && pwd -P)" "$base"
    return 0
  fi
  probe="$absolute"
  suffix=""
  while [[ "$probe" != "/" && ! -e "$probe" ]]; do
    suffix="/$(basename "$probe")$suffix"
    probe="$(dirname "$probe")"
  done
  if [[ -d "$probe" ]]; then
    resolved_root="$(cd "$probe" && pwd -P)"
    if [[ "$resolved_root" == "/" ]]; then
      printf '%s\n' "$suffix"
    else
      printf '%s%s\n' "$resolved_root" "$suffix"
    fi
    return 0
  fi
  while [[ "$absolute" == *"/./"* ]]; do
    absolute="${absolute//\/.\//\/}"
  done
  printf '%s\n' "$absolute"
}

resolve_command_path_from_cwd() {
  local value="$1"
  if [[ -z "$value" || "$value" != */* ]]; then
    printf '%s\n' "$value"
  else
    resolve_path_from_cwd "$value"
  fi
}

run() {
  echo "+ $(quote_cmd "$@")"
  if [[ "$DRY_RUN" -eq 0 ]]; then
    "$@"
  fi
}

json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"
}

write_evidence() {
  local name="$1"
  local status="$2"
  local command="$3"
  local duration_ms="$4"
  local trace_root="$5"

  if [[ -z "$EVIDENCE_OUT" ]]; then
    return 0
  fi

  local metadata_json=""
  if [[ "$name" == "Android hardware pilot" && -n "$ANDROID_APP_ID" ]]; then
    metadata_json+=",\"androidAppId\":$(json_escape "$ANDROID_APP_ID")"
  fi
  if [[ "$name" == "Android hardware pilot" && -n "$ANDROID_APP_ROOT" ]]; then
    metadata_json+=",\"androidAppRoot\":$(json_escape "$ANDROID_APP_ROOT")"
  fi
  if [[ "$name" == "Android hardware pilot" && -n "$ANDROID_DEVICE" ]]; then
    metadata_json+=",\"androidDeviceId\":$(json_escape "$ANDROID_DEVICE")"
  fi
  if [[ "$name" == "physical iOS readiness" && -n "$IOS_DEVICE" ]]; then
    metadata_json+=",\"iosDeviceId\":$(json_escape "$IOS_DEVICE")"
  fi
  if [[ "$name" == "iOS simulator hardware pilot" && -n "$IOS_APP_ID" ]]; then
    metadata_json+=",\"iosAppId\":$(json_escape "$IOS_APP_ID")"
  fi
  if [[ "$name" == "iOS simulator hardware pilot" && -n "$IOS_APP_ROOT" ]]; then
    metadata_json+=",\"iosAppRoot\":$(json_escape "$IOS_APP_ROOT")"
  fi
  if [[ "$name" == "iOS simulator hardware pilot" && -n "$IOS_APP_PATH" ]]; then
    metadata_json+=",\"iosAppPath\":$(json_escape "$IOS_APP_PATH")"
  fi
  if [[ "$name" == "iOS simulator hardware pilot" && -n "$IOS_DEVICE" ]]; then
    metadata_json+=",\"iosDeviceId\":$(json_escape "$IOS_DEVICE")"
  fi
  if [[ "$name" == "iOS physical hardware pilot" ]]; then
    if [[ -n "$IOS_APP_ID" ]]; then
      metadata_json+=",\"iosAppId\":$(json_escape "$IOS_APP_ID")"
    fi
    if [[ -n "$IOS_APP_ROOT" ]]; then
      metadata_json+=",\"iosAppRoot\":$(json_escape "$IOS_APP_ROOT")"
    fi
    if [[ -n "$IOS_APP_PATH" ]]; then
      metadata_json+=",\"iosAppPath\":$(json_escape "$IOS_APP_PATH")"
    fi
    if [[ -n "$IOS_DEVICE" ]]; then
      metadata_json+=",\"iosDeviceId\":$(json_escape "$IOS_DEVICE")"
    fi
  fi

  printf '{"name":%s,"mode":"pilot-gate","status":%s,"durationMs":%s,"command":%s,"traceRoot":%s,"runs":%s,"minPassRate":%s,"maxFailures":%s%s}\n' \
    "$(json_escape "$name")" \
    "$(json_escape "$status")" \
    "$duration_ms" \
    "$(json_escape "$command")" \
    "$(json_escape "$trace_root")" \
    "$RUNS" \
    "$MIN_PASS_RATE" \
    "$MAX_FAILURES" \
    "$metadata_json" >> "$EVIDENCE_OUT"
}

run_step() {
  local name="$1"
  local trace_root="$2"
  shift 2

  local start end duration status command
  command="$(quote_cmd "$@")"
  echo "+ $command"
  start="$(date +%s)"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    status="planned"
  else
    set +e
    "$@"
    local command_status=$?
    set -e
    if [[ "$command_status" -eq 0 ]]; then
      status="passed"
    else
      status="failed"
    fi
  fi
  end="$(date +%s)"
  duration="$(( (end - start) * 1000 ))"
  write_evidence "$name" "$status" "$command" "$duration" "$trace_root"
  [[ "$status" != "failed" ]] || exit 1
}

validate_number() {
  local name="$1"
  local value="$2"
  if [[ ! "$value" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
    die "$name must be a non-negative number"
  fi
}

validate_integer() {
  local name="$1"
  local value="$2"
  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    die "$name must be a non-negative integer"
  fi
}

validate_optional_integer() {
  local name="$1"
  local value="$2"
  if [[ -n "$value" && ! "$value" =~ ^[0-9]+$ ]]; then
    die "$name must be a non-negative integer"
  fi
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
    --android)
      ANDROID_SELECTED=1
      shift
      ;;
    --ios)
      IOS_SELECTED=1
      shift
      ;;
    --android-app-root)
      ANDROID_APP_ROOT="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --android-app-id)
      ANDROID_APP_ID="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --android-device)
      ANDROID_DEVICE="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --android-apk)
      ANDROID_APK="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --android-scenario)
      ANDROID_SCENARIO="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --adb)
      ADB="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --skip-emulator)
      ANDROID_SKIP_EMULATOR=1
      shift
      ;;
    --skip-metro)
      ANDROID_SKIP_METRO=1
      shift
      ;;
    --ios-app-root)
      IOS_APP_ROOT="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --ios-app-id)
      IOS_APP_ID="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --ios-device)
      IOS_DEVICE="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --ios-device-type)
      IOS_DEVICE_TYPE="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --ios-app-path)
      IOS_APP_PATH="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --ios-shim)
      IOS_SHIM="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --xcrun)
      XCRUN="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --zmr-bin)
      ZMR_BIN="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --trace-root)
      TRACE_ROOT="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --evidence-out)
      EVIDENCE_OUT="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --runs)
      RUNS="$(require_value "$1" "${2-}")"
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
    --android-max-p95-ms)
      ANDROID_MAX_P95_MS="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --ios-max-p95-ms)
      IOS_MAX_P95_MS="$(require_value "$1" "${2-}")"
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

if [[ "$ANDROID_SELECTED" -eq 0 && "$IOS_SELECTED" -eq 0 ]]; then
  ANDROID_SELECTED=1
  IOS_SELECTED=1
fi

validate_integer "--runs" "$RUNS"
[[ "$RUNS" -ge 1 ]] || die "--runs must be a positive integer"
validate_number "--min-pass-rate" "$MIN_PASS_RATE"
validate_integer "--max-failures" "$MAX_FAILURES"
validate_optional_integer "--max-mean-ms" "$MAX_MEAN_MS"
validate_integer "--android-max-p95-ms" "$ANDROID_MAX_P95_MS"
validate_integer "--ios-max-p95-ms" "$IOS_MAX_P95_MS"
[[ "$IOS_DEVICE_TYPE" == "simulator" || "$IOS_DEVICE_TYPE" == "physical" ]] || die "--ios-device-type must be simulator or physical"

if [[ "$ANDROID_SELECTED" -eq 1 && -z "$ANDROID_APP_ROOT" ]]; then
  die "--android-app-root is required when --android is selected"
fi

if [[ "$IOS_SELECTED" -eq 1 && -z "$IOS_APP_PATH" ]]; then
  die "--ios-app-path is required when --ios is selected"
fi
if [[ "$IOS_SELECTED" -eq 1 && -z "$IOS_APP_ROOT" ]]; then
  die "--ios-app-root is required when --ios is selected"
fi

TRACE_ROOT="$(resolve_path_from_cwd "$TRACE_ROOT")"
if [[ -n "$EVIDENCE_OUT" ]]; then
  EVIDENCE_OUT="$(resolve_path_from_cwd "$EVIDENCE_OUT")"
fi
if [[ -n "$ANDROID_APP_ROOT" ]]; then
  ANDROID_APP_ROOT="$(resolve_path_from_cwd "$ANDROID_APP_ROOT")"
fi
if [[ -n "$ANDROID_APK" ]]; then
  ANDROID_APK="$(resolve_path_from_cwd "$ANDROID_APK")"
fi
if [[ -n "$ANDROID_SCENARIO" ]]; then
  ANDROID_SCENARIO="$(resolve_path_from_cwd "$ANDROID_SCENARIO")"
fi
if [[ -n "$ADB" ]]; then
  ADB="$(resolve_command_path_from_cwd "$ADB")"
fi
if [[ -n "$IOS_APP_ROOT" ]]; then
  IOS_APP_ROOT="$(resolve_path_from_cwd "$IOS_APP_ROOT")"
fi
if [[ -n "$IOS_APP_PATH" ]]; then
  IOS_APP_PATH="$(resolve_path_from_cwd "$IOS_APP_PATH")"
fi
if [[ -n "$IOS_SHIM" ]]; then
  IOS_SHIM="$(resolve_command_path_from_cwd "$IOS_SHIM")"
fi
if [[ -n "$XCRUN" ]]; then
  XCRUN="$(resolve_command_path_from_cwd "$XCRUN")"
fi
if [[ -n "$ZMR_BIN" ]]; then
  ZMR_BIN="$(resolve_command_path_from_cwd "$ZMR_BIN")"
fi

echo "Pilot gate output: $TRACE_ROOT"
if [[ -n "$EVIDENCE_OUT" ]]; then
  echo "pilot evidence: $EVIDENCE_OUT"
  mkdir -p "$(dirname "$EVIDENCE_OUT")"
  : > "$EVIDENCE_OUT"
fi
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "DRY RUN: commands will be printed but not executed"
fi

common_gate_args=(--runs "$RUNS" --min-pass-rate "$MIN_PASS_RATE" --max-failures "$MAX_FAILURES")
if [[ -n "$MAX_MEAN_MS" ]]; then
  common_gate_args+=(--max-mean-ms "$MAX_MEAN_MS")
fi

if [[ "$ANDROID_SELECTED" -eq 1 ]]; then
  android_cmd=("$ROOT/scripts/run-android-pilot.sh" --app-root "$ANDROID_APP_ROOT" --device "$ANDROID_DEVICE" --trace-root "$TRACE_ROOT/android" --max-p95-ms "$ANDROID_MAX_P95_MS")
  if [[ -n "$ANDROID_APP_ID" ]]; then
    android_cmd+=(--app-id "$ANDROID_APP_ID")
  fi
  if [[ -n "$ANDROID_APK" ]]; then
    android_cmd+=(--apk "$ANDROID_APK")
  fi
  if [[ -n "$ANDROID_SCENARIO" ]]; then
    android_cmd+=(--scenario "$ANDROID_SCENARIO")
  fi
  if [[ -n "$ADB" ]]; then
    android_cmd+=(--adb "$ADB")
  fi
  if [[ -n "$ZMR_BIN" ]]; then
    android_cmd+=(--zmr-bin "$ZMR_BIN")
  fi
  if [[ "$ANDROID_SKIP_EMULATOR" -eq 1 ]]; then
    android_cmd+=(--skip-emulator)
  fi
  if [[ "$ANDROID_SKIP_METRO" -eq 1 ]]; then
    android_cmd+=(--skip-metro)
  fi
  android_cmd+=("${common_gate_args[@]}")
  run_step "Android hardware pilot" "$TRACE_ROOT/android" "${android_cmd[@]}"
fi

if [[ "$IOS_SELECTED" -eq 1 ]]; then
  if [[ "$IOS_DEVICE_TYPE" == "physical" ]]; then
    readiness_cmd=("$ROOT/scripts/assert-ios-physical-ready.sh" --device "$IOS_DEVICE")
    if [[ -n "$ZMR_BIN" ]]; then
      readiness_cmd+=(--zmr "$ZMR_BIN")
    fi
    if [[ -n "$XCRUN" ]]; then
      readiness_cmd+=(--xcrun "$XCRUN")
    fi
    run_step "physical iOS readiness" "$TRACE_ROOT/ios" "${readiness_cmd[@]}"
  fi
  ios_cmd=("$ROOT/scripts/run-ios-pilot.sh" --app-path "$IOS_APP_PATH" --device "$IOS_DEVICE" --ios-device-type "$IOS_DEVICE_TYPE" --trace-root "$TRACE_ROOT/ios" --max-p95-ms "$IOS_MAX_P95_MS")
  if [[ -n "$IOS_APP_ROOT" ]]; then
    ios_cmd+=(--app-root "$IOS_APP_ROOT")
  fi
  if [[ -n "$IOS_APP_ID" ]]; then
    ios_cmd+=(--app-id "$IOS_APP_ID")
  fi
  if [[ -n "$IOS_SHIM" ]]; then
    ios_cmd+=(--ios-shim "$IOS_SHIM")
  fi
  if [[ -n "$XCRUN" ]]; then
    ios_cmd+=(--xcrun "$XCRUN")
  fi
  if [[ -n "$ZMR_BIN" ]]; then
    ios_cmd+=(--zmr-bin "$ZMR_BIN")
  fi
  ios_cmd+=("${common_gate_args[@]}")
  if [[ "$IOS_DEVICE_TYPE" == "physical" ]]; then
    run_step "iOS physical hardware pilot" "$TRACE_ROOT/ios" "${ios_cmd[@]}"
  else
    run_step "iOS simulator hardware pilot" "$TRACE_ROOT/ios" "${ios_cmd[@]}"
  fi
fi
