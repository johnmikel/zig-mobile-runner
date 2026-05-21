#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for args in "boot --avd" "wait-ready --device" "snapshot-save --name"; do
  set +e
  missing_value_output="$("$ROOT/scripts/android-emulator.sh" $args 2>&1)"
  missing_value_status=$?
  set -e
  if [[ "$missing_value_status" -ne 2 ]]; then
    echo "android-emulator should exit 2 for missing value: $args" >&2
    exit 1
  fi
  flag="${args##* }"
  grep -q -- "$flag requires a value" <<< "$missing_value_output"
done

boot_output="$("$ROOT/scripts/android-emulator.sh" boot --avd Small_Phone --dry-run)"
[[ "$boot_output" == *"emulator -avd Small_Phone -no-snapshot-load"* ]]

wait_output="$("$ROOT/scripts/android-emulator.sh" wait-ready --device emulator-5554 --dry-run)"
[[ "$wait_output" == *"adb -s emulator-5554 wait-for-device"* ]]
[[ "$wait_output" == *"wait until sys.boot_completed is 1"* ]]

snapshot_output="$("$ROOT/scripts/android-emulator.sh" snapshot-save --device emulator-5554 --name zmr-clean --dry-run)"
[[ "$snapshot_output" == *"adb -s emulator-5554 emu avd snapshot save zmr-clean"* ]]
