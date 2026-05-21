#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Some sandboxed environments do not allow writing to the default temp directory
# (/var/folders, /tmp). Use a repo-local TMPDIR so heredocs/mktemp/adb/xcrun work.
if [[ -z "${TMPDIR:-}" || ! -w "${TMPDIR:-/nonexistent}" ]]; then
  TMPDIR="$ROOT/traces/tmp"
  mkdir -p "$TMPDIR"
  export TMPDIR
fi


MODE="local"
DRY_RUN=0
RUNS="20"
LOCAL_ANDROID_DEMO_RUNS="5"
LOCAL_ANDROID_DEVICE="emulator-5554"
LOCAL_ANDROID_AVD=""
LOCAL_IOS_DEMO_RUNS="5"
EVIDENCE_DIR="traces/release-candidate/$(date +%Y%m%d-%H%M%S)"

ANDROID_APP_ROOT="/path/to/mobile-app"
ANDROID_APP_ID="com.example.mobiletest"
ANDROID_DEVICE="emulator-5554"
IOS_APP_ROOT="/path/to/mobile-app"
IOS_APP_PATH="/path/to/mobile-app/build/Debug-iphonesimulator/Sample.app"
IOS_APP_ID="com.example.mobiletest"
IOS_DEVICE="booted"
IOS_SHIM="/path/to/mobile-app/.zmr/ios-shim"
XCRUN="xcrun"
IOS_PHYSICAL_APP_ROOT="/path/to/mobile-app"
IOS_PHYSICAL_APP_PATH="/path/to/mobile-app/build/Release-iphoneos/Sample.ipa"
IOS_PHYSICAL_APP_ID="com.example.mobiletest"
IOS_PHYSICAL_DEVICE="<physical-device-id>"
IOS_PHYSICAL_SHIM="/path/to/mobile-app/.zmr/ios-shim"

usage() {
  printf '%s\n' \
    'Usage:' \
    '  scripts/release-candidate.sh [options]' \
    '' \
    'Runs or prints the release-candidate evidence gate. Use local mode for a' \
    'hardware-free release-candidate check, hardware mode for app/device pilots, and' \
    'all mode for both.' \
    '' \
    'Options:' \
    '  --mode <local|hardware|all>      Gate mode. Default: local.' \
    '  --dry-run                        Print commands and write planned evidence.' \
    '  --evidence-dir <path>            Evidence directory. Default: traces/release-candidate/<timestamp>.' \
    '  --runs <n>                       Hardware pilot repeated-run count. Default: 20.' \
    '  --local-android-demo-runs <n>     Public Android demo repeated-run count when --local-android-avd is set. Default: 5.' \
    '  --local-android-device <serial>   Public Android demo device serial. Default: emulator-5554.' \
    '  --local-android-avd <name>        Run the public Android demo on this AVD in local/all mode.' \
    '  --local-ios-demo-runs <n>         Public iOS demo repeated-run count in local/all mode. Default: 5.' \
    '  --android-app-root <path>        App root for Android pilot.' \
    '  --android-app-id <id>            Android application id. Default: com.example.mobiletest.' \
    '  --android-device <serial>        Android device/emulator serial. Default: emulator-5554.' \
    '  --ios-app-root <path>            App root for iOS simulator pilot.' \
    '  --ios-app-path <path>            Built simulator .app for iOS simulator pilot.' \
    '  --ios-app-id <id>                iOS simulator bundle id. Default: com.example.mobiletest.' \
    '  --ios-device <udid|booted>       iOS simulator device. Default: booted.' \
    '  --ios-shim <path>                iOS simulator XCTest shim command.' \
    '  --xcrun <path>                   xcrun binary used by iOS readiness and pilots. Default: xcrun.' \
    '  --ios-physical-app-root <path>   App root for physical iOS pilot.' \
    '  --ios-physical-app-path <path>   Signed physical-device .app/.ipa.' \
    '  --ios-physical-app-id <id>       Physical iOS bundle id. Default: com.example.mobiletest.' \
    '  --ios-physical-device <id>       Physical iOS CoreDevice identifier from `zmr devices`.' \
    '  --ios-physical-shim <path>       Physical iOS XCTest shim command.' \
    '  -h, --help                       Show this help.'
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

json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1"
}

quote_cmd() {
  local quoted=()
  local arg
  for arg in "$@"; do
    quoted+=("$(printf '%q' "$arg")")
  done
  printf '%s\n' "${quoted[*]}"
}

write_evidence() {
  local name="$1"
  local mode="$2"
  local status="$3"
  local command="$4"
  local duration_ms="$5"
  local metadata_json=""
  case "$name" in
    "Android hardware pilot")
      metadata_json+=",\"androidAppRoot\":$(json_escape "$ANDROID_APP_ROOT")"
      metadata_json+=",\"androidAppId\":$(json_escape "$ANDROID_APP_ID")"
      metadata_json+=",\"androidDeviceId\":$(json_escape "$ANDROID_DEVICE")"
      metadata_json+=",\"runs\":$RUNS,\"minPassRate\":100,\"maxFailures\":0"
      ;;
    "iOS simulator hardware pilot")
      metadata_json+=",\"iosAppRoot\":$(json_escape "$IOS_APP_ROOT")"
      metadata_json+=",\"iosAppPath\":$(json_escape "$IOS_APP_PATH")"
      metadata_json+=",\"iosAppId\":$(json_escape "$IOS_APP_ID")"
      metadata_json+=",\"iosDeviceId\":$(json_escape "$IOS_DEVICE")"
      metadata_json+=",\"runs\":$RUNS,\"minPassRate\":100,\"maxFailures\":0"
      ;;
    "iOS physical hardware pilot")
      metadata_json+=",\"iosAppRoot\":$(json_escape "$IOS_PHYSICAL_APP_ROOT")"
      metadata_json+=",\"iosAppPath\":$(json_escape "$IOS_PHYSICAL_APP_PATH")"
      metadata_json+=",\"iosAppId\":$(json_escape "$IOS_PHYSICAL_APP_ID")"
      metadata_json+=",\"iosDeviceId\":$(json_escape "$IOS_PHYSICAL_DEVICE")"
      metadata_json+=",\"runs\":$RUNS,\"minPassRate\":100,\"maxFailures\":0"
      ;;
    "physical iOS readiness")
      metadata_json+=",\"iosDeviceId\":$(json_escape "$IOS_PHYSICAL_DEVICE")"
      ;;
  esac
  printf '{"name":%s,"mode":%s,"status":%s,"durationMs":%s,"command":%s%s}\n' \
    "$(json_escape "$name")" \
    "$(json_escape "$mode")" \
    "$(json_escape "$status")" \
    "$duration_ms" \
    "$(json_escape "$command")" \
    "$metadata_json" >> "$EVIDENCE_JSONL"
}

run_step() {
  local name="$1"
  shift
  local start end duration status
  local command
  command="$(quote_cmd "$@")"
  printf '+ %s\n' "$command"
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
  write_evidence "$name" "$MODE" "$status" "$command" "$duration"
  [[ "$status" != "failed" ]] || exit 1
}

append_evidence_file() {
  local file="$1"
  if [[ -f "$file" ]]; then
    cat "$file" >> "$EVIDENCE_JSONL"
  fi
}

run_pilot_gate_step() {
  local evidence_file="$1"
  shift
  local command
  command="$(quote_cmd "$@")"
  printf '+ %s\n' "$command"
  set +e
  if [[ "$DRY_RUN" -eq 1 ]]; then
    "$@" --dry-run
  else
    "$@"
  fi
  local command_status=$?
  set -e
  append_evidence_file "$evidence_file"
  [[ "$command_status" -eq 0 ]] || exit "$command_status"
}

contains_placeholder() {
  case "$1" in
    *"/path/to/"*|"<physical-device-id>"|"")
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

validate_hardware_inputs() {
  local missing=0
  for value in \
    "$ANDROID_APP_ROOT" \
    "$ANDROID_DEVICE" \
    "$IOS_APP_ROOT" \
    "$IOS_APP_PATH" \
    "$IOS_DEVICE" \
    "$IOS_SHIM" \
    "$IOS_PHYSICAL_APP_ROOT" \
    "$IOS_PHYSICAL_APP_PATH" \
    "$IOS_PHYSICAL_DEVICE" \
    "$IOS_PHYSICAL_SHIM"; do
    if contains_placeholder "$value"; then
      missing=1
    fi
  done
  if [[ "$missing" -eq 1 ]]; then
    die "hardware mode requires replacing placeholder paths before publish"
  fi
}

write_summary() {
  local status="passed"
  local readiness_target="dev-preview"
  local readiness_status=0
  local readiness_command
  if grep -q '"status":"failed"' "$EVIDENCE_JSONL"; then
    status="failed"
  elif grep -q '"status":"planned"' "$EVIDENCE_JSONL"; then
    status="planned"
  fi
  if [[ "$MODE" == "hardware" || "$MODE" == "all" ]]; then
    readiness_target="production"
  fi
  readiness_command="$(quote_cmd ./scripts/release-readiness.sh --evidence "$EVIDENCE_JSONL" --target "$readiness_target")"

  {
    echo "# ZMR Release Candidate Evidence"
    echo
    echo "- Mode: \`$MODE\`"
    echo "- Status: \`$status\`"
    echo "- Evidence: \`$EVIDENCE_JSONL\`"
    echo
    echo "## Steps"
    echo
    python3 - "$EVIDENCE_JSONL" <<'PY'
import json
import sys

for line in open(sys.argv[1], encoding="utf-8"):
    row = json.loads(line)
    print(f"- `{row['status']}` {row['name']}: `{row['command']}`")
PY
    echo
    echo "## Readiness"
    echo
    echo "\`$readiness_command\`"
    echo
    set +e
    "./scripts/release-readiness.sh" --evidence "$EVIDENCE_JSONL" --target "$readiness_target"
    readiness_status=$?
    set -e
    if [[ "$readiness_status" -ne 0 ]]; then
      true
    fi
  } > "$SUMMARY_MD"

  echo "wrote $EVIDENCE_JSONL"
  echo "wrote $SUMMARY_MD"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --evidence-dir)
      EVIDENCE_DIR="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --runs)
      RUNS="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --local-android-demo-runs)
      LOCAL_ANDROID_DEMO_RUNS="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --local-android-device)
      LOCAL_ANDROID_DEVICE="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --local-android-avd)
      LOCAL_ANDROID_AVD="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --local-ios-demo-runs)
      LOCAL_IOS_DEMO_RUNS="$(require_value "$1" "${2-}")"
      shift 2
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
    --ios-app-root)
      IOS_APP_ROOT="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --ios-app-path)
      IOS_APP_PATH="$(require_value "$1" "${2-}")"
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
    --ios-shim)
      IOS_SHIM="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --xcrun)
      XCRUN="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --ios-physical-app-root)
      IOS_PHYSICAL_APP_ROOT="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --ios-physical-app-path)
      IOS_PHYSICAL_APP_PATH="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --ios-physical-app-id)
      IOS_PHYSICAL_APP_ID="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --ios-physical-device)
      IOS_PHYSICAL_DEVICE="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --ios-physical-shim)
      IOS_PHYSICAL_SHIM="$(require_value "$1" "${2-}")"
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

[[ "$MODE" == "local" || "$MODE" == "hardware" || "$MODE" == "all" ]] || die "--mode must be local, hardware, or all"
[[ "$RUNS" =~ ^[0-9]+$ && "$RUNS" -ge 1 ]] || die "--runs must be a positive integer"
[[ "$LOCAL_ANDROID_DEMO_RUNS" =~ ^[0-9]+$ && "$LOCAL_ANDROID_DEMO_RUNS" -ge 1 ]] || die "--local-android-demo-runs must be a positive integer"
[[ -n "$LOCAL_ANDROID_DEVICE" ]] || die "--local-android-device must not be empty"
[[ "$LOCAL_IOS_DEMO_RUNS" =~ ^[0-9]+$ && "$LOCAL_IOS_DEMO_RUNS" -ge 1 ]] || die "--local-ios-demo-runs must be a positive integer"
if [[ "$DRY_RUN" -eq 0 && ( "$MODE" == "hardware" || "$MODE" == "all" ) ]]; then
  validate_hardware_inputs
fi

mkdir -p "$EVIDENCE_DIR"
EVIDENCE_JSONL="$EVIDENCE_DIR/evidence.jsonl"
SUMMARY_MD="$EVIDENCE_DIR/summary.md"
: > "$EVIDENCE_JSONL"

echo "release candidate mode: $MODE"
echo "release candidate evidence: $EVIDENCE_DIR"
if [[ "$DRY_RUN" -eq 1 && ( "$MODE" == "hardware" || "$MODE" == "all" ) ]]; then
  echo "hardware mode requires replacing placeholder paths before publish"
fi

if [[ "$MODE" == "local" || "$MODE" == "all" ]]; then
  run_step "local release gate" ./scripts/release-gate.sh
  if [[ -n "$LOCAL_ANDROID_AVD" ]]; then
    run_step "public Android emulator demo" ./scripts/demo-android-real.sh --out "$EVIDENCE_DIR/android-demo" --device "$LOCAL_ANDROID_DEVICE" --avd "$LOCAL_ANDROID_AVD" --runs "$LOCAL_ANDROID_DEMO_RUNS" --trace-root "$EVIDENCE_DIR/android-demo/traces/pilot"
  else
    run_step "public Android demo app build" ./scripts/create-android-demo-app.sh --out "$EVIDENCE_DIR/android-demo"
  fi
  run_step "public iOS simulator demo" ./scripts/demo-ios-real.sh --out "$EVIDENCE_DIR/ios-demo" --device booted --runs "$LOCAL_IOS_DEMO_RUNS" --trace-root "$EVIDENCE_DIR/ios-demo/traces/pilot" --cleanup-build-products
fi

if [[ "$MODE" == "hardware" || "$MODE" == "all" ]]; then
  run_pilot_gate_step "$EVIDENCE_DIR/hardware-pilot/evidence.jsonl" ./scripts/pilot-gate.sh --android --ios --android-app-root "$ANDROID_APP_ROOT" --android-app-id "$ANDROID_APP_ID" --android-device "$ANDROID_DEVICE" --ios-app-root "$IOS_APP_ROOT" --ios-app-path "$IOS_APP_PATH" --ios-app-id "$IOS_APP_ID" --ios-device "$IOS_DEVICE" --ios-shim "$IOS_SHIM" --xcrun "$XCRUN" --runs "$RUNS" --min-pass-rate 100 --max-failures 0 --trace-root "$EVIDENCE_DIR/hardware-pilot" --evidence-out "$EVIDENCE_DIR/hardware-pilot/evidence.jsonl"
  run_pilot_gate_step "$EVIDENCE_DIR/ios-physical-pilot/evidence.jsonl" ./scripts/pilot-gate.sh --ios --ios-device-type physical --ios-device "$IOS_PHYSICAL_DEVICE" --ios-app-root "$IOS_PHYSICAL_APP_ROOT" --ios-app-path "$IOS_PHYSICAL_APP_PATH" --ios-app-id "$IOS_PHYSICAL_APP_ID" --ios-shim "$IOS_PHYSICAL_SHIM" --xcrun "$XCRUN" --runs "$RUNS" --min-pass-rate 100 --max-failures 0 --trace-root "$EVIDENCE_DIR/ios-physical-pilot" --evidence-out "$EVIDENCE_DIR/ios-physical-pilot/evidence.jsonl"
fi

write_summary
