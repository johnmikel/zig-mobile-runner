#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="/tmp/zmr-ios-demo-$(date +%Y%m%d-%H%M%S)"
APP_NAME="ZMRDemo"
APP_ID="com.example.mobiletest"
DEVICE="booted"
DEPLOYMENT_TARGET="16.0"
RUNS="1"
TRACE_ROOT=""
DRY_RUN=0

usage() {
  cat <<'USAGE'
Usage:
  scripts/demo-ios-real.sh [options]

Creates a generic public iOS simulator demo app, builds it, and runs the real
ZMR iOS pilot with the generated XCTest shim.

Options:
  --out <dir>                  Demo app output directory. Default: /tmp/zmr-ios-demo-<timestamp>.
  --name <name>                App target name. Default: ZMRDemo.
  --app-id <id>                App bundle id. Default: com.example.mobiletest.
  --device <udid|booted>       Simulator target. Default: booted.
  --deployment-target <ver>    iOS deployment target. Default: 16.0.
  --runs <n>                   Pilot run count. Default: 1.
  --trace-root <dir>           Trace output directory. Default: <out>/traces/pilot.
  --dry-run                    Print commands without executing them.
  -h, --help                   Show this help.
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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)
      OUT="${2:-}"
      shift 2
      ;;
    --name)
      APP_NAME="${2:-}"
      shift 2
      ;;
    --app-id)
      APP_ID="${2:-}"
      shift 2
      ;;
    --device)
      DEVICE="${2:-}"
      shift 2
      ;;
    --deployment-target)
      DEPLOYMENT_TARGET="${2:-}"
      shift 2
      ;;
    --runs)
      RUNS="${2:-}"
      shift 2
      ;;
    --trace-root)
      TRACE_ROOT="${2:-}"
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

[[ -n "$OUT" ]] || die "--out must not be empty"
[[ "$APP_NAME" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die "--name must be a valid Swift identifier"
[[ "$RUNS" =~ ^[0-9]+$ && "$RUNS" -ge 1 ]] || die "--runs must be a positive integer"

if [[ -z "$TRACE_ROOT" ]]; then
  TRACE_ROOT="$OUT/traces/pilot"
fi

PROJECT_PATH="$OUT/ios/$APP_NAME.xcodeproj"
DERIVED_DATA="$OUT/DerivedData"
APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/$APP_NAME.app"
IOS_SHIM="$OUT/.zmr/ios-shim"

echo "iOS real demo app: $OUT"
echo "iOS real demo traces: $TRACE_ROOT"
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "DRY RUN: commands will be printed but not executed"
fi

run "$ROOT/scripts/create-ios-demo-app.sh" \
  --out "$OUT" \
  --name "$APP_NAME" \
  --bundle-id "$APP_ID" \
  --deployment-target "$DEPLOYMENT_TARGET"

run xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$APP_NAME" \
  -destination "generic/platform=iOS Simulator" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  build

run "$ROOT/scripts/run-ios-pilot.sh" \
  --app-root "$OUT" \
  --app-path "$APP_PATH" \
  --device "$DEVICE" \
  --app-id "$APP_ID" \
  --ios-shim "$IOS_SHIM" \
  --runs "$RUNS" \
  --trace-root "$TRACE_ROOT"

cat <<EOF

iOS real demo complete.
App directory: $OUT
Trace directory: $TRACE_ROOT
EOF
