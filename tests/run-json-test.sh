#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZMR="$ROOT/zig-out/bin/zmr"
PASS_TRACE="$ROOT/traces/test-run-json-pass"
FAIL_TRACE="$ROOT/traces/test-run-json-fail"
OMIT_BUNDLE="$ROOT/traces/test-run-json-omit-screenshots.zmrtrace"

rm -rf "$PASS_TRACE" "$FAIL_TRACE"
rm -f "$OMIT_BUNDLE"

PASS_OUTPUT="$("$ZMR" run "$ROOT/examples/demo-fake.json" \
  --device fake-android-1 \
  --adb "$ROOT/tests/fake-adb.sh" \
  --trace-dir "$PASS_TRACE" \
  --json)"
grep -q '"ok":true' <<< "$PASS_OUTPUT"
grep -q '"status":"passed"' <<< "$PASS_OUTPUT"
grep -q '"scenario":"ZMR fake Android auth probe demo"' <<< "$PASS_OUTPUT"
grep -q '"appId":"com.example.mobiletest"' <<< "$PASS_OUTPUT"
grep -q '"traceDir":' <<< "$PASS_OUTPUT"
grep -q '"eventsPath":"events.jsonl"' <<< "$PASS_OUTPUT"
grep -q '"eventCount":' <<< "$PASS_OUTPUT"
grep -q '"snapshotCount":' <<< "$PASS_OUTPUT"

"$ZMR" export "$PASS_TRACE" --out "$OMIT_BUNDLE" --redact --omit-screenshots
if tar -tf "$OMIT_BUNDLE" | grep -q '[.]png$'; then
  echo "redacted export with --omit-screenshots should not include PNG screenshots" >&2
  exit 1
fi
tar -xOf "$OMIT_BUNDLE" trace.json | grep -q '"screenshots":"omitted"'
tar -xOf "$OMIT_BUNDLE" trace.json | grep -q '"screenshotsOmitted":true'
tar -xOf "$OMIT_BUNDLE" trace.json | grep -q '"screenshotsRedacted":false'

set +e
FAIL_OUTPUT="$("$ZMR" run "$ROOT/examples/demo-failure.json" \
  --device fake-android-1 \
  --adb "$ROOT/tests/fake-adb.sh" \
  --trace-dir "$FAIL_TRACE" \
  --json 2> "$FAIL_TRACE.expected-error.log")"
FAIL_STATUS=$?
set -e

if [[ "$FAIL_STATUS" -eq 0 ]]; then
  echo "expected failing scenario to keep non-zero exit status" >&2
  exit 1
fi
grep -q '"ok":false' <<< "$FAIL_OUTPUT"
grep -q '"status":"failed"' <<< "$FAIL_OUTPUT"
grep -q '"failedStepIndex":1' <<< "$FAIL_OUTPUT"
grep -q '"error":"WaitTimeout"' <<< "$FAIL_OUTPUT"
grep -q '"traceDir":' <<< "$FAIL_OUTPUT"
