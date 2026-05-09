#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZMR="$ROOT/zig-out/bin/zmr"
test -x "$ZMR"

ANDROID_JSON="$("$ZMR" devices --json --adb "$ROOT/tests/fake-adb.sh")"
grep -q '"platform":"android"' <<< "$ANDROID_JSON"
grep -q '"count":1' <<< "$ANDROID_JSON"
grep -q '"serial":"fake-android-1"' <<< "$ANDROID_JSON"
grep -q '"state":"device"' <<< "$ANDROID_JSON"

IOS_JSON="$("$ZMR" devices --json --platform ios --xcrun "$ROOT/tests/fake-xcrun.sh")"
grep -q '"platform":"ios"' <<< "$IOS_JSON"
grep -q '"count":1' <<< "$IOS_JSON"
grep -q '"serial":"fake-ios-1"' <<< "$IOS_JSON"
grep -q '"state":"Booted"' <<< "$IOS_JSON"

IOS_PHYSICAL_JSON="$("$ZMR" devices --json --platform ios --ios-device-type physical --xcrun "$ROOT/tests/fake-xcrun.sh")"
grep -q '"platform":"ios"' <<< "$IOS_PHYSICAL_JSON"
grep -q '"count":1' <<< "$IOS_PHYSICAL_JSON"
grep -q '"serial":"fake-physical-ios-1"' <<< "$IOS_PHYSICAL_JSON"
grep -q '"state":"connected"' <<< "$IOS_PHYSICAL_JSON"

IOS_ALL_JSON="$("$ZMR" devices --json --platform ios --ios-device-type all --xcrun "$ROOT/tests/fake-xcrun.sh")"
grep -q '"count":2' <<< "$IOS_ALL_JSON"
