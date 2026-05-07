#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_ROOT="${APP_ROOT:-}"
DEVICE="${DEVICE:-emulator-5554}"
AVD="${AVD:-}"
TRACE_ROOT="${TRACE_ROOT:-$ROOT/traces/android-app-pilot-$(date +%Y%m%d-%H%M%S)}"
ZMR_BIN="${ZMR_BIN:-$ROOT/zig-out/bin/zmr}"
ADB="${ADB:-adb}"
APK="${APK:-}"
APP_ID="${APP_ID:-com.example.mobiletest}"
RUNS="${RUNS:-1}"
MIN_PASS_RATE="${MIN_PASS_RATE:-100}"
MAX_FAILURES="${MAX_FAILURES:-0}"
MAX_MEAN_MS="${MAX_MEAN_MS:-}"
MAX_P95_MS="${MAX_P95_MS:-}"
RESTORE_SNAPSHOT="${RESTORE_SNAPSHOT:-}"
DRY_RUN=0
SKIP_EMULATOR=0
SKIP_METRO=0
KEEP_RUNNING=0
RESET_EMULATOR=0
SCREEN_RECORD=0
STARTED_EMULATOR=0
METRO_PID=""
SCREEN_RECORD_PID=""
SCREEN_RECORD_REMOTE="/sdcard/zmr-pilot-screenrecord.mp4"
SCREEN_RECORD_LOCAL=""

usage() {
  cat <<'USAGE'
Usage:
  scripts/run-android-pilot.sh [options]

Runs a configurable Android sample-app pilot end to end:
  1. build/validate zmr
  2. boot or use an emulator
  3. install the sample app test APK
  4. optionally start the sample app's Metro environment
  5. run auth and login smoke scenarios
  6. generate reports and normal/redacted .zmrtrace bundles

Options:
  --app-root <dir>    Sample app repo containing .env.test and the debug APK.
  --app-id <bundle>    Application id. Default: com.example.mobiletest.
  --apk <path>          APK to install. Defaults to android/app/build/outputs/apk/debug/app-debug.apk.
  --device <serial>     Android serial. Default: emulator-5554.
  --avd <name>          AVD to boot when no device is attached. Defaults to first local AVD.
  --trace-root <dir>    Output directory. Default: traces/android-app-pilot-<timestamp>.
  --zmr-bin <path>      zmr binary. Default: zig-out/bin/zmr.
  --adb <path>          adb path. Default: adb.
  --runs <n>            Run each flow n times. n=1 writes trace bundles; n>1 writes benchmark reports.
  --min-pass-rate <pct> Repeated-run gate minimum. Default: 100.
  --max-failures <n>    Repeated-run gate maximum. Default: 0.
  --max-mean-ms <ms>    Optional repeated-run mean duration maximum.
  --max-p95-ms <ms>     Optional repeated-run p95 duration maximum.
  --reset-emulator      Kill the target emulator before booting/restoring it.
  --restore-snapshot <name>
                        Boot the AVD from a named emulator snapshot.
  --screen-record       Capture a pilot-level MP4 with adb shell screenrecord.
  --skip-emulator       Require/use an already booted device.
  --skip-metro          Do not start Metro; assume it is already running.
  --keep-running        Leave Metro/emulator running when this script exits.
  --dry-run             Print the commands without executing them.
  -h, --help            Show this help.

Environment:
  APP_ROOT, APP_ID, APK, DEVICE, AVD, TRACE_ROOT, ZMR_BIN, ADB, RUNS,
  RESTORE_SNAPSHOT, MIN_PASS_RATE, MAX_FAILURES, MAX_MEAN_MS, MAX_P95_MS.

Notes:
  Metro output is written to <trace-root>/metro.log and may contain app secrets.
  Share the generated *-redacted.zmrtrace bundles, not raw Metro logs.
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

capture() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo ""
  else
    "$@"
  fi
}

wait_for_device() {
  echo "+ wait for adb device $DEVICE"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    return
  fi
  for _ in $(seq 1 120); do
    if "$ADB" devices | awk -v serial="$DEVICE" '$1 == serial && $2 == "device" { found = 1 } END { exit found ? 0 : 1 }'; then
      return
    fi
    sleep 2
  done
  die "Android device did not appear: $DEVICE"
}

wait_for_boot() {
  echo "+ wait for Android boot completion on $DEVICE"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    return
  fi
  for _ in $(seq 1 120); do
    booted="$("$ADB" -s "$DEVICE" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
    if [[ "$booted" == "1" ]]; then
      return
    fi
    sleep 2
  done
  die "Android device did not finish booting: $DEVICE"
}

cleanup() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    return
  fi
  if [[ -n "$SCREEN_RECORD_PID" ]]; then
    kill "$SCREEN_RECORD_PID" >/dev/null 2>&1 || true
    wait "$SCREEN_RECORD_PID" >/dev/null 2>&1 || true
    "$ADB" -s "$DEVICE" pull "$SCREEN_RECORD_REMOTE" "$SCREEN_RECORD_LOCAL" >/dev/null 2>&1 || true
    "$ADB" -s "$DEVICE" shell rm -f "$SCREEN_RECORD_REMOTE" >/dev/null 2>&1 || true
  fi
  if [[ -n "$METRO_PID" ]]; then
    kill "$METRO_PID" >/dev/null 2>&1 || true
    wait "$METRO_PID" >/dev/null 2>&1 || true
  fi
  if [[ "$KEEP_RUNNING" -eq 1 ]]; then
    return
  fi
  if [[ "$STARTED_EMULATOR" -eq 1 ]]; then
    "$ADB" -s "$DEVICE" emu kill >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

start_screen_recording() {
  if [[ "$SCREEN_RECORD" -ne 1 ]]; then
    return 0
  fi
  SCREEN_RECORD_LOCAL="$TRACE_ROOT/screenrecord.mp4"
  run "$ADB" -s "$DEVICE" shell rm -f "$SCREEN_RECORD_REMOTE"
  echo "+ $(quote_cmd "$ADB" -s "$DEVICE" shell screenrecord "$SCREEN_RECORD_REMOTE")"
  if [[ "$DRY_RUN" -eq 0 ]]; then
    "$ADB" -s "$DEVICE" shell screenrecord "$SCREEN_RECORD_REMOTE" > "$TRACE_ROOT/screenrecord.log" 2>&1 &
    SCREEN_RECORD_PID="$!"
  fi
}

stop_screen_recording() {
  if [[ "$SCREEN_RECORD" -ne 1 ]]; then
    return 0
  fi
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "+ stop adb screenrecord"
    run "$ADB" -s "$DEVICE" pull "$SCREEN_RECORD_REMOTE" "$TRACE_ROOT/screenrecord.mp4"
    run "$ADB" -s "$DEVICE" shell rm -f "$SCREEN_RECORD_REMOTE"
    return
  fi
  if [[ -n "$SCREEN_RECORD_PID" ]]; then
    kill "$SCREEN_RECORD_PID" >/dev/null 2>&1 || true
    wait "$SCREEN_RECORD_PID" >/dev/null 2>&1 || true
    SCREEN_RECORD_PID=""
  fi
  run "$ADB" -s "$DEVICE" pull "$SCREEN_RECORD_REMOTE" "$SCREEN_RECORD_LOCAL"
  run "$ADB" -s "$DEVICE" shell rm -f "$SCREEN_RECORD_REMOTE"
}

preflight_android_device() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    return 0
  fi
  if "$ADB" devices | awk -v serial="$DEVICE" '$1 == serial && $2 == "device" { found = 1 } END { exit found ? 0 : 1 }'; then
    return 0
  fi
  echo "error: no Android device found: $DEVICE" >&2
  echo "errorCode: setup.android.no_devices" >&2
  echo "hint: run zmr doctor --json --adb $(printf '%q' "$ADB") and start/connect the requested device." >&2
  "$ZMR_BIN" doctor --json --adb "$ADB" >&2 || true
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-root)
      APP_ROOT="${2:-}"
      shift 2
      ;;
    --app-id)
      APP_ID="${2:-}"
      shift 2
      ;;
    --apk)
      APK="${2:-}"
      shift 2
      ;;
    --device)
      DEVICE="${2:-}"
      shift 2
      ;;
    --avd)
      AVD="${2:-}"
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
    --adb)
      ADB="${2:-}"
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
    --reset-emulator)
      RESET_EMULATOR=1
      shift
      ;;
    --restore-snapshot)
      RESTORE_SNAPSHOT="${2:-}"
      shift 2
      ;;
    --screen-record)
      SCREEN_RECORD=1
      shift
      ;;
    --skip-emulator)
      SKIP_EMULATOR=1
      shift
      ;;
    --skip-metro)
      SKIP_METRO=1
      shift
      ;;
    --keep-running)
      KEEP_RUNNING=1
      shift
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

[[ -n "$DEVICE" ]] || die "--device cannot be empty"
[[ "$RUNS" =~ ^[0-9]+$ && "$RUNS" -ge 1 ]] || die "--runs must be a positive integer"
[[ "$MIN_PASS_RATE" =~ ^[0-9]+([.][0-9]+)?$ ]] || die "--min-pass-rate must be a non-negative number"
[[ "$MAX_FAILURES" =~ ^[0-9]+$ ]] || die "--max-failures must be a non-negative integer"
[[ -z "$MAX_MEAN_MS" || "$MAX_MEAN_MS" =~ ^[0-9]+$ ]] || die "--max-mean-ms must be a non-negative integer"
[[ -z "$MAX_P95_MS" || "$MAX_P95_MS" =~ ^[0-9]+$ ]] || die "--max-p95-ms must be a non-negative integer"

[[ -n "$APP_ROOT" ]] || die "--app-root is required"
[[ -d "$APP_ROOT" ]] || die "app repo not found: $APP_ROOT"
[[ -f "$APP_ROOT/.env.test" ]] || die "app test env file not found: $APP_ROOT/.env.test"

if [[ -z "$APK" ]]; then
  APK="$APP_ROOT/android/app/build/outputs/apk/debug/app-debug.apk"
fi
[[ -f "$APK" ]] || die "APK not found: $APK"

echo "Android pilot output: $TRACE_ROOT"
echo "App test env: $APP_ROOT/.env.test"
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
run "$ZMR_BIN" validate examples/android-app-auth-probe.json
run "$ZMR_BIN" validate examples/android-app-login-smoke.json

run_zmr_android_scenario() {
  if [[ "$ADB" == "adb" ]]; then
    run "$ZMR_BIN" run "$@"
  else
    run "$ZMR_BIN" run "$@" --adb "$ADB"
  fi
}

run_android_benchmark() {
  if [[ "$ADB" == "adb" ]]; then
    ZMR_BIN="$ZMR_BIN" run "$ROOT/scripts/benchmark.sh" "$@"
  else
    ZMR_BIN="$ZMR_BIN" run "$ROOT/scripts/benchmark.sh" "$@" --adb "$ADB"
  fi
}

if [[ "$SKIP_EMULATOR" -eq 0 ]]; then
  if [[ "$RESET_EMULATOR" -eq 1 ]]; then
    run "$ADB" -s "$DEVICE" emu kill
    STARTED_EMULATOR=1
  fi
  attached="$(capture "$ADB" devices | awk -v serial="$DEVICE" '$1 == serial && $2 == "device" { print $1 }')"
  if [[ -z "$attached" || "$RESET_EMULATOR" -eq 1 ]]; then
    if [[ -z "$AVD" ]]; then
      AVD="$(find "$HOME/.android/avd" -maxdepth 1 -name '*.ini' -print 2>/dev/null | sed -n '1s#.*/##;s#\.ini$##p')"
    fi
    [[ -n "$AVD" ]] || die "no AVD found; pass --avd or --skip-emulator"
    emulator_bin="${ANDROID_HOME:-$HOME/Library/Android/sdk}/emulator/emulator"
    [[ -x "$emulator_bin" ]] || die "emulator binary not found: $emulator_bin"
    emulator_args=(-avd "$AVD" -no-window -gpu swiftshader_indirect -no-snapshot-save -no-audio -no-boot-anim)
    if [[ -n "$RESTORE_SNAPSHOT" ]]; then
      emulator_args+=(-snapshot "$RESTORE_SNAPSHOT")
    else
      emulator_args+=(-no-snapshot-load)
    fi
    echo "+ $(quote_cmd "$emulator_bin" "${emulator_args[@]}")"
    if [[ "$DRY_RUN" -eq 0 ]]; then
      "$emulator_bin" "${emulator_args[@]}" > "$TRACE_ROOT/emulator.log" 2>&1 &
      STARTED_EMULATOR=1
    fi
  fi
fi

if [[ "$SKIP_EMULATOR" -eq 1 ]]; then
  preflight_android_device
fi
wait_for_device
wait_for_boot

run "$ADB" -s "$DEVICE" install -r "$APK"
run "$ADB" -s "$DEVICE" reverse tcp:8081 tcp:8081
run "$ADB" -s "$DEVICE" shell settings put global window_animation_scale 0
run "$ADB" -s "$DEVICE" shell settings put global transition_animation_scale 0
run "$ADB" -s "$DEVICE" shell settings put global animator_duration_scale 0

if [[ "$SKIP_METRO" -eq 0 ]]; then
  command -v bun >/dev/null 2>&1 || die "bun is required to start Metro"
  echo "+ (cd $(printf '%q' "$APP_ROOT") && bun run test:start > $(printf '%q' "$TRACE_ROOT/metro.log") 2>&1 &)"
  if [[ "$DRY_RUN" -eq 0 ]]; then
    (cd "$APP_ROOT" && bun run test:start > "$TRACE_ROOT/metro.log" 2>&1) &
    METRO_PID="$!"
    for _ in $(seq 1 90); do
      if lsof -nP -iTCP:8081 -sTCP:LISTEN >/dev/null 2>&1; then
        break
      fi
      sleep 1
    done
  fi
else
  echo "Skipping Metro start; assuming app test server is already running"
fi

start_screen_recording

if [[ "$RUNS" -eq 1 ]]; then
  AUTH_TRACE="$TRACE_ROOT/auth"
  LOGIN_TRACE="$TRACE_ROOT/login-smoke"
  run rm -rf "$AUTH_TRACE" "$LOGIN_TRACE"
  run_zmr_android_scenario examples/android-app-auth-probe.json --device "$DEVICE" --app-id "$APP_ID" --trace-dir "$AUTH_TRACE"
  run "$ZMR_BIN" report "$AUTH_TRACE" --out "$AUTH_TRACE/report.html"
  run "$ZMR_BIN" export "$AUTH_TRACE" --out "$TRACE_ROOT/auth.zmrtrace"
  run "$ZMR_BIN" export "$AUTH_TRACE" --out "$TRACE_ROOT/auth-redacted.zmrtrace" --redact
  run_zmr_android_scenario examples/android-app-login-smoke.json --device "$DEVICE" --app-id "$APP_ID" --trace-dir "$LOGIN_TRACE"
  run "$ZMR_BIN" report "$LOGIN_TRACE" --out "$LOGIN_TRACE/report.html"
  run "$ZMR_BIN" export "$LOGIN_TRACE" --out "$TRACE_ROOT/login-smoke.zmrtrace"
  run "$ZMR_BIN" export "$LOGIN_TRACE" --out "$TRACE_ROOT/login-smoke-redacted.zmrtrace" --redact
else
  benchmark_gate_args=(--min-pass-rate "$MIN_PASS_RATE" --max-failures "$MAX_FAILURES")
  if [[ -n "$MAX_MEAN_MS" ]]; then
    benchmark_gate_args+=(--max-mean-ms "$MAX_MEAN_MS")
  fi
  if [[ -n "$MAX_P95_MS" ]]; then
    benchmark_gate_args+=(--max-p95-ms "$MAX_P95_MS")
  fi
  run_android_benchmark --zmr examples/android-app-auth-probe.json --device "$DEVICE" --app-id "$APP_ID" --runs "$RUNS" --trace-root "$TRACE_ROOT/bench-auth" "${benchmark_gate_args[@]}"
  run "$ZMR_BIN" report "$TRACE_ROOT/bench-auth" --out "$TRACE_ROOT/bench-auth/report.html"
  run_android_benchmark --zmr examples/android-app-login-smoke.json --device "$DEVICE" --app-id "$APP_ID" --runs "$RUNS" --trace-root "$TRACE_ROOT/bench-login-smoke" "${benchmark_gate_args[@]}"
  run "$ZMR_BIN" report "$TRACE_ROOT/bench-login-smoke" --out "$TRACE_ROOT/bench-login-smoke/report.html"
fi

stop_screen_recording

cat <<EOF

Android pilot complete.
Output directory: $TRACE_ROOT
Shareable bundles:
  $TRACE_ROOT/auth-redacted.zmrtrace
  $TRACE_ROOT/login-smoke-redacted.zmrtrace
Viewer:
  $ROOT/viewer/index.html
EOF

if [[ "$SCREEN_RECORD" -eq 1 ]]; then
  cat <<EOF
Screen recording:
  $TRACE_ROOT/screenrecord.mp4
EOF
fi
