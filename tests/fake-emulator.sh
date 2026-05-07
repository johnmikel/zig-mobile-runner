#!/usr/bin/env bash
set -euo pipefail

LOG="${ZMR_FAKE_EMULATOR_LOG:-zig-cache/test-android-emulator-preflight-process.log}"
if [[ "${1:-}" == "-list-avds" ]]; then
  printf '%s\n' "${ZMR_FAKE_AVD_LIST:-}"
  exit 0
fi
printf 'emulator %s\n' "$*" >> "$LOG"
sleep 0.05
