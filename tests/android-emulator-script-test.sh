#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

boot_output="$("$ROOT/scripts/android-emulator.sh" boot --avd Small_Phone --dry-run)"
[[ "$boot_output" == *"emulator -avd Small_Phone -no-snapshot-load"* ]]

wait_output="$("$ROOT/scripts/android-emulator.sh" wait-ready --device emulator-5554 --dry-run)"
[[ "$wait_output" == *"adb -s emulator-5554 wait-for-device"* ]]
[[ "$wait_output" == *"wait until sys.boot_completed is 1"* ]]

snapshot_output="$("$ROOT/scripts/android-emulator.sh" snapshot-save --device emulator-5554 --name zmr-clean --dry-run)"
[[ "$snapshot_output" == *"adb -s emulator-5554 emu avd snapshot save zmr-clean"* ]]

