#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZMR="$ROOT/zig-out/bin/zmr"
TRACE_DIR="$ROOT/traces/test-explain-json"

rm -rf "$TRACE_DIR"
mkdir -p "$TRACE_DIR"

if "$ZMR" run "$ROOT/examples/demo-failure.json" \
  --device fake-android-1 \
  --adb "$ROOT/tests/fake-adb.sh" \
  --trace-dir "$TRACE_DIR" \
  2> "$TRACE_DIR/expected-error.log"; then
  echo "expected demo failure scenario to fail" >&2
  exit 1
fi

OUTPUT="$("$ZMR" explain "$TRACE_DIR" --json)"
grep -q '"ok":true' <<< "$OUTPUT"
grep -q '"scenario":"ZMR fake failure explanation demo"' <<< "$OUTPUT"
grep -q '"status":"failed"' <<< "$OUTPUT"
grep -q '"appId":"com.example.mobiletest"' <<< "$OUTPUT"
grep -q '"failedStepIndex":1' <<< "$OUTPUT"
grep -q '"error":"WaitTimeout"' <<< "$OUTPUT"
grep -q '"diagnostic":{"kind":"wait.visible","status":"timeout"' <<< "$OUTPUT"
grep -q '"snapshotId":"snapshot-1"' <<< "$OUTPUT"
grep -q '"activePackage":"com.example.mobiletest"' <<< "$OUTPUT"
grep -q '"visibleTexts":' <<< "$OUTPUT"
grep -q '"nearestTextMatches":' <<< "$OUTPUT"
grep -q '"lastEvent":"scenario.end"' <<< "$OUTPUT"
