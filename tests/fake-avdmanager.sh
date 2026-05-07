#!/usr/bin/env bash
set -euo pipefail

LOG="${ZMR_FAKE_EMULATOR_LOG:-zig-cache/test-android-emulator-preflight-process.log}"
printf 'avdmanager %s\n' "$*" >> "$LOG"
