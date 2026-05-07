#!/usr/bin/env bash
set -euo pipefail

AVD="${AVD:-}"
DEVICE="${DEVICE:-emulator-5554}"
EMULATOR="${EMULATOR:-emulator}"
ADB="${ADB:-adb}"
SNAPSHOT="${SNAPSHOT:-zmr-clean}"
DRY_RUN=0

usage() {
  cat <<'USAGE'
Usage:
  scripts/android-emulator.sh boot --avd <name> [--device emulator-5554] [--dry-run]
  scripts/android-emulator.sh wait-ready [--device emulator-5554] [--dry-run]
  scripts/android-emulator.sh snapshot-save [--device emulator-5554] [--name zmr-clean] [--dry-run]
  scripts/android-emulator.sh snapshot-load --avd <name> [--name zmr-clean] [--dry-run]
  scripts/android-emulator.sh kill [--device emulator-5554] [--dry-run]

Environment:
  EMULATOR    emulator binary. Defaults to emulator.
  ADB         adb binary. Defaults to adb.
  AVD         default AVD name.
  DEVICE      default adb serial.
  SNAPSHOT    default snapshot name.
USAGE
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

die() {
  echo "error: $*" >&2
  exit 2
}

[[ $# -gt 0 ]] || {
  usage >&2
  exit 2
}

COMMAND="$1"
shift

while [[ $# -gt 0 ]]; do
  case "$1" in
    --avd)
      AVD="${2:-}"
      shift 2
      ;;
    --device)
      DEVICE="${2:-}"
      shift 2
      ;;
    --name)
      SNAPSHOT="${2:-}"
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

case "$COMMAND" in
  boot)
    [[ -n "$AVD" ]] || die "--avd or AVD is required"
    run "$EMULATOR" -avd "$AVD" -no-snapshot-load -netdelay none -netspeed full
    ;;
  wait-ready)
    run "$ADB" -s "$DEVICE" wait-for-device
    if [[ "$DRY_RUN" -eq 1 ]]; then
      echo "+ wait until sys.boot_completed is 1"
      exit 0
    fi
    for _ in $(seq 1 120); do
      value="$("$ADB" -s "$DEVICE" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')"
      [[ "$value" == "1" ]] && exit 0
      sleep 2
    done
    die "emulator did not finish booting"
    ;;
  snapshot-save)
    run "$ADB" -s "$DEVICE" emu avd snapshot save "$SNAPSHOT"
    ;;
  snapshot-load)
    [[ -n "$AVD" ]] || die "--avd or AVD is required"
    run "$EMULATOR" -avd "$AVD" -snapshot "$SNAPSHOT" -netdelay none -netspeed full
    ;;
  kill)
    run "$ADB" -s "$DEVICE" emu kill
    ;;
  *)
    die "unknown command: $COMMAND"
    ;;
esac

