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
cd "$ROOT"

if [[ -n "${ZMR_BIN:-}" ]]; then
  ZMR="$ZMR_BIN"
elif [[ -x "$ROOT/zig-out/bin/zmr" ]]; then
  ZMR="$ROOT/zig-out/bin/zmr"
else
  ZMR="zmr"
fi
DEVICE=""
XCRUN=""
XCRUN_PROVIDED=0
EVIDENCE_OUT=""
ATTEMPTS="${ZMR_IOS_READY_ATTEMPTS:-3}"
RETRY_DELAY_SECONDS="${ZMR_IOS_READY_RETRY_DELAY_SECONDS:-1}"
START_MS="$(python3 - <<'PY'
import time
print(int(time.time() * 1000))
PY
)"

usage() {
  cat <<'USAGE'
Usage:
  scripts/assert-ios-physical-ready.sh [--zmr <path>] [--xcrun <path>] [--device <identifier>] [--evidence-out <path>]

Fails unless zmr reports at least one ready physical iOS device. When --device
is supplied, that exact CoreDevice identifier from `zmr devices --json
--platform ios --ios-device-type physical` must be present and ready.

When --evidence-out is supplied, a successful check appends a JSONL row that
can be consumed by zmr-release-readiness.
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

append_evidence() {
  [[ -n "$EVIDENCE_OUT" ]] || return 0

  local end_ms duration_ms command
  end_ms="$(python3 - <<'PY'
import time
print(int(time.time() * 1000))
PY
)"
  duration_ms="$((end_ms - START_MS))"
  if [[ -n "$DEVICE" ]]; then
    command="scripts/assert-ios-physical-ready.sh --device $DEVICE"
  else
    command="scripts/assert-ios-physical-ready.sh"
  fi
  if [[ -n "$XCRUN" ]]; then
    command="$command --xcrun $XCRUN"
  fi

  mkdir -p "$(dirname "$EVIDENCE_OUT")"
  python3 - "$EVIDENCE_OUT" "physical iOS readiness" "ios-physical-ready" "passed" "$duration_ms" "$command" "$DEVICE" <<'PY'
import json
import sys

path, name, mode, status, duration_ms, command, device_id = sys.argv[1:]
row = {
    "name": name,
    "mode": mode,
    "status": status,
    "durationMs": int(duration_ms),
    "command": command,
}
if device_id:
    row["deviceId"] = device_id
with open(path, "a", encoding="utf-8") as fh:
    fh.write(json.dumps(row, separators=(",", ":")) + "\n")
PY
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --zmr)
      ZMR="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --xcrun)
      XCRUN="$(require_value "$1" "${2-}")"
      XCRUN_PROVIDED=1
      shift 2
      ;;
    --device)
      DEVICE="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --evidence-out)
      EVIDENCE_OUT="$(require_value "$1" "${2-}")"
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

[[ -n "$ZMR" ]] || die "--zmr must be non-empty"
if [[ "$XCRUN_PROVIDED" -eq 1 && -z "$XCRUN" ]]; then
  die "--xcrun must be non-empty"
fi
[[ "$ATTEMPTS" =~ ^[0-9]+$ && "$ATTEMPTS" -ge 1 ]] || die "ZMR_IOS_READY_ATTEMPTS must be a positive integer"
[[ "$RETRY_DELAY_SECONDS" =~ ^[0-9]+$ ]] || die "ZMR_IOS_READY_RETRY_DELAY_SECONDS must be a non-negative integer"

devices_json=""
last_error=""
attempt=1
zmr_devices_args=(devices --json --platform ios --ios-device-type physical)
if [[ -n "$XCRUN" ]]; then
  zmr_devices_args+=(--xcrun "$XCRUN")
fi
while [[ "$attempt" -le "$ATTEMPTS" ]]; do
  error_file="$(mktemp)"
  if devices_json="$("$ZMR" "${zmr_devices_args[@]}" 2>"$error_file")"; then
    rm -f "$error_file"
    break
  fi
  last_error="$(cat "$error_file")"
  rm -f "$error_file"
  if [[ "$attempt" -lt "$ATTEMPTS" ]]; then
    sleep "$RETRY_DELAY_SECONDS"
  fi
  attempt="$((attempt + 1))"
done

if [[ -z "$devices_json" ]]; then
  if [[ -n "$last_error" ]]; then
    printf '%s\n' "$last_error" >&2
  fi
  echo "error[setup.ios.physical_devices_unavailable]: unable to list physical iOS devices after $ATTEMPTS attempt(s)" >&2
  exit 3
fi

if ZMR_DEVICES_JSON="$devices_json" python3 - "$DEVICE" <<'PY'
import json
import os
import sys

target = sys.argv[1] or None

try:
    data = json.loads(os.environ["ZMR_DEVICES_JSON"])
except Exception as exc:
    print(f"error[setup.ios.devices_json_invalid]: failed to parse zmr devices JSON: {exc}", file=sys.stderr)
    sys.exit(3)

devices = data.get("devices")
if not isinstance(devices, list):
    print("error[setup.ios.devices_json_invalid]: zmr devices JSON is missing devices[]", file=sys.stderr)
    sys.exit(3)

if target:
    for device in devices:
        if device.get("serial") == target:
            if device.get("ready") is True:
                print(f"physical iOS device ready: {target}")
                sys.exit(0)
            state = device.get("state") or "unknown"
            print(
                f"error[setup.ios.physical_device_not_ready]: physical iOS device is not ready: {target} (state: {state})",
                file=sys.stderr,
            )
            sys.exit(3)
    print(f"error[setup.ios.physical_device_not_found]: physical iOS device was not found: {target}", file=sys.stderr)
    sys.exit(3)

for device in devices:
    if device.get("ready") is True:
        print(f"physical iOS device ready: {device.get('serial', '<unknown>')}")
        sys.exit(0)

states = ", ".join(f"{d.get('serial', '<unknown>')}:{d.get('state', 'unknown')}" for d in devices) or "none"
print(f"error[setup.ios.no_ready_physical_devices]: no ready physical iOS devices found ({states})", file=sys.stderr)
sys.exit(3)
PY
then
  append_evidence
else
  exit $?
fi
