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

ANDROID_SELECTED=0
IOS_SELECTED=0
ANDROID_APP_ROOT="${ANDROID_APP_ROOT:-}"
ANDROID_APP_ID="${ANDROID_APP_ID:-}"
ANDROID_DEVICE="${ANDROID_DEVICE:-emulator-5554}"
ANDROID_APK="${ANDROID_APK:-}"
ANDROID_SKIP_EMULATOR=0
ANDROID_SKIP_METRO=0
ADB="${ADB:-}"
IOS_APP_ROOT="${IOS_APP_ROOT:-}"
IOS_APP_ID="${IOS_APP_ID:-}"
IOS_DEVICE="${IOS_DEVICE:-booted}"
IOS_APP_PATH="${IOS_APP_PATH:-}"
IOS_SHIM="${IOS_SHIM:-}"
XCRUN="${XCRUN:-}"
TRACE_ROOT="${TRACE_ROOT:-$CALLER_CWD/traces/pilot-gate-$(date +%Y%m%d-%H%M%S)}"
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
  --adb <path>              adb path forwarded to the Android pilot.
  --skip-emulator           Require/use an already booted Android device.
  --skip-metro              Do not start the app test server for Android.

iOS options:
  --ios-app-path <path>     Built simulator .app. Required when iOS is selected.
  --ios-app-root <dir>      Optional app repo root for iOS output context.
  --ios-app-id <id>         iOS bundle id. Defaults to the pilot wrapper default.
  --ios-device <udid>       Simulator UDID or booted. Default: booted.
  --ios-shim <path>         XCTest shim command for selector-grade iOS runs.
  --xcrun <path>            xcrun path forwarded to the iOS pilot.

Gate options:
  --trace-root <dir>        Output root. Default: traces/pilot-gate-<timestamp>.
  --runs <n>                Repeated run count. Default: 20.
  --min-pass-rate <pct>     Minimum pass rate. Default: 100.
  --max-failures <n>        Maximum failed runs. Default: 0.
  --max-mean-ms <ms>        Optional mean duration maximum for both platforms.
  --android-max-p95-ms <ms> Android p95 duration maximum. Default: 30000.
  --ios-max-p95-ms <ms>     iOS p95 duration maximum. Default: 45000.
  --dry-run                 Print commands without executing them.
  -h, --help                Show this help.

Environment defaults mirror the upper-case option names, for example
ANDROID_APP_ROOT, IOS_APP_PATH, ADB, XCRUN, RUNS, and TRACE_ROOT.
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
    printf '%s%s\n' "$(cd "$probe" && pwd -P)" "$suffix"
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
      ANDROID_APP_ROOT="${2:-}"
      shift 2
      ;;
    --android-app-id)
      ANDROID_APP_ID="${2:-}"
      shift 2
      ;;
    --android-device)
      ANDROID_DEVICE="${2:-}"
      shift 2
      ;;
    --android-apk)
      ANDROID_APK="${2:-}"
      shift 2
      ;;
    --adb)
      ADB="${2:-}"
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
      IOS_APP_ROOT="${2:-}"
      shift 2
      ;;
    --ios-app-id)
      IOS_APP_ID="${2:-}"
      shift 2
      ;;
    --ios-device)
      IOS_DEVICE="${2:-}"
      shift 2
      ;;
    --ios-app-path)
      IOS_APP_PATH="${2:-}"
      shift 2
      ;;
    --ios-shim)
      IOS_SHIM="${2:-}"
      shift 2
      ;;
    --xcrun)
      XCRUN="${2:-}"
      shift 2
      ;;
    --trace-root)
      TRACE_ROOT="${2:-}"
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
    --android-max-p95-ms)
      ANDROID_MAX_P95_MS="${2:-}"
      shift 2
      ;;
    --ios-max-p95-ms)
      IOS_MAX_P95_MS="${2:-}"
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

if [[ "$ANDROID_SELECTED" -eq 1 && -z "$ANDROID_APP_ROOT" ]]; then
  die "--android-app-root is required when --android is selected"
fi

if [[ "$IOS_SELECTED" -eq 1 && -z "$IOS_APP_PATH" ]]; then
  die "--ios-app-path is required when --ios is selected"
fi

TRACE_ROOT="$(resolve_path_from_cwd "$TRACE_ROOT")"
if [[ -n "$ANDROID_APP_ROOT" ]]; then
  ANDROID_APP_ROOT="$(resolve_path_from_cwd "$ANDROID_APP_ROOT")"
fi
if [[ -n "$ANDROID_APK" ]]; then
  ANDROID_APK="$(resolve_path_from_cwd "$ANDROID_APK")"
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

echo "Pilot gate output: $TRACE_ROOT"
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
  if [[ -n "$ADB" ]]; then
    android_cmd+=(--adb "$ADB")
  fi
  if [[ "$ANDROID_SKIP_EMULATOR" -eq 1 ]]; then
    android_cmd+=(--skip-emulator)
  fi
  if [[ "$ANDROID_SKIP_METRO" -eq 1 ]]; then
    android_cmd+=(--skip-metro)
  fi
  android_cmd+=("${common_gate_args[@]}")
  run "${android_cmd[@]}"
fi

if [[ "$IOS_SELECTED" -eq 1 ]]; then
  ios_cmd=("$ROOT/scripts/run-ios-pilot.sh" --app-path "$IOS_APP_PATH" --device "$IOS_DEVICE" --trace-root "$TRACE_ROOT/ios" --max-p95-ms "$IOS_MAX_P95_MS")
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
  ios_cmd+=("${common_gate_args[@]}")
  run "${ios_cmd[@]}"
fi
