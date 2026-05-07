#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZMR="$ROOT/zig-out/bin/zmr"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

VALID_OUTPUT="$("$ZMR" validate "$ROOT/examples/demo-fake.json" --json)"
grep -q '"ok":true' <<< "$VALID_OUTPUT"
grep -q '"path":"'"$ROOT"'/examples/demo-fake.json"' <<< "$VALID_OUTPUT"
grep -q '"name":"ZMR fake Android auth probe demo"' <<< "$VALID_OUTPUT"
grep -q '"stepCount":4' <<< "$VALID_OUTPUT"

cat > "$TMPDIR/bad.json" <<'JSON'
{"name":"bad"}
JSON

set +e
INVALID_OUTPUT="$("$ZMR" validate "$TMPDIR/bad.json" --json)"
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  echo "expected validate --json to exit non-zero for invalid scenario" >&2
  exit 1
fi

grep -q '"ok":false' <<< "$INVALID_OUTPUT"
grep -q '"path":"'"$TMPDIR"'/bad.json"' <<< "$INVALID_OUTPUT"
grep -q '"errorCode":"scenario.invalid"' <<< "$INVALID_OUTPUT"
grep -q '"message":"scenario is invalid"' <<< "$INVALID_OUTPUT"
grep -q '"fieldPath":"$.steps"' <<< "$INVALID_OUTPUT"

cat > "$TMPDIR/missing-selector.json" <<'JSON'
{"name":"bad","steps":[{"action":"tap"}]}
JSON

set +e
MISSING_SELECTOR_OUTPUT="$("$ZMR" validate "$TMPDIR/missing-selector.json" --json)"
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  echo "expected validate --json to exit non-zero for a missing selector" >&2
  exit 1
fi

grep -q '"ok":false' <<< "$MISSING_SELECTOR_OUTPUT"
grep -q '"errorCode":"selector.invalid"' <<< "$MISSING_SELECTOR_OUTPUT"
grep -q '"message":"selector is invalid"' <<< "$MISSING_SELECTOR_OUTPUT"
grep -q '"fieldPath":"$.steps\[\].selector"' <<< "$MISSING_SELECTOR_OUTPUT"

cat > "$TMPDIR/unknown-action.json" <<'JSON'
{"name":"bad","steps":[{"action":"tapp"}]}
JSON

set +e
UNKNOWN_ACTION_OUTPUT="$("$ZMR" validate "$TMPDIR/unknown-action.json" --json)"
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  echo "expected validate --json to exit non-zero for an unknown action" >&2
  exit 1
fi

grep -q '"ok":false' <<< "$UNKNOWN_ACTION_OUTPUT"
grep -q '"errorCode":"scenario.invalid"' <<< "$UNKNOWN_ACTION_OUTPUT"
grep -q '"message":"scenario is invalid"' <<< "$UNKNOWN_ACTION_OUTPUT"
grep -q '"fieldPath":"$.steps\[\].action"' <<< "$UNKNOWN_ACTION_OUTPUT"
grep -q '"line":1' <<< "$UNKNOWN_ACTION_OUTPUT"
grep -q '"column":25' <<< "$UNKNOWN_ACTION_OUTPUT"

cat > "$TMPDIR/unknown-direction.json" <<'JSON'
{"name":"bad","steps":[{"action":"scrollUntilVisible","selector":{"text":"Dashboard"},"direction":"sideways"}]}
JSON

set +e
UNKNOWN_DIRECTION_OUTPUT="$("$ZMR" validate "$TMPDIR/unknown-direction.json" --json)"
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  echo "expected validate --json to exit non-zero for an unknown scroll direction" >&2
  exit 1
fi

grep -q '"ok":false' <<< "$UNKNOWN_DIRECTION_OUTPUT"
grep -q '"errorCode":"scenario.invalid"' <<< "$UNKNOWN_DIRECTION_OUTPUT"
grep -q '"message":"scenario is invalid"' <<< "$UNKNOWN_DIRECTION_OUTPUT"
grep -q '"fieldPath":"$.steps\[\].direction"' <<< "$UNKNOWN_DIRECTION_OUTPUT"
grep -q '"line":1' <<< "$UNKNOWN_DIRECTION_OUTPUT"

cat > "$TMPDIR/missing-url.json" <<'JSON'
{"name":"bad","steps":[{"action":"openLink"}]}
JSON

set +e
MISSING_URL_OUTPUT="$("$ZMR" validate "$TMPDIR/missing-url.json" --json)"
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  echo "expected validate --json to exit non-zero for a missing openLink url" >&2
  exit 1
fi

grep -q '"ok":false' <<< "$MISSING_URL_OUTPUT"
grep -q '"errorCode":"scenario.invalid"' <<< "$MISSING_URL_OUTPUT"
grep -q '"message":"scenario is invalid"' <<< "$MISSING_URL_OUTPUT"
grep -q '"fieldPath":"$.steps\[\].url"' <<< "$MISSING_URL_OUTPUT"

cat > "$TMPDIR/missing-text.json" <<'JSON'
{"name":"bad","steps":[{"action":"typeText","selector":{"resourceId":"email-input"}}]}
JSON

set +e
MISSING_TEXT_OUTPUT="$("$ZMR" validate "$TMPDIR/missing-text.json" --json)"
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  echo "expected validate --json to exit non-zero for a missing typeText text value" >&2
  exit 1
fi

grep -q '"ok":false' <<< "$MISSING_TEXT_OUTPUT"
grep -q '"errorCode":"scenario.invalid"' <<< "$MISSING_TEXT_OUTPUT"
grep -q '"message":"scenario is invalid"' <<< "$MISSING_TEXT_OUTPUT"
grep -q '"fieldPath":"$.steps\[\].text"' <<< "$MISSING_TEXT_OUTPUT"

cat > "$TMPDIR/missing-x1.json" <<'JSON'
{"name":"bad","steps":[{"action":"swipe","y1":1,"x2":2,"y2":3}]}
JSON

set +e
MISSING_X1_OUTPUT="$("$ZMR" validate "$TMPDIR/missing-x1.json" --json)"
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  echo "expected validate --json to exit non-zero for a missing swipe x1 value" >&2
  exit 1
fi

grep -q '"ok":false' <<< "$MISSING_X1_OUTPUT"
grep -q '"errorCode":"scenario.invalid"' <<< "$MISSING_X1_OUTPUT"
grep -q '"message":"scenario is invalid"' <<< "$MISSING_X1_OUTPUT"
grep -q '"fieldPath":"$.steps\[\].x1"' <<< "$MISSING_X1_OUTPUT"

cat > "$TMPDIR/missing-y1.json" <<'JSON'
{"name":"bad","steps":[{"action":"swipe","x1":1,"x2":2,"y2":3}]}
JSON

set +e
MISSING_Y1_OUTPUT="$("$ZMR" validate "$TMPDIR/missing-y1.json" --json)"
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  echo "expected validate --json to exit non-zero for a missing swipe y1 value" >&2
  exit 1
fi

grep -q '"ok":false' <<< "$MISSING_Y1_OUTPUT"
grep -q '"errorCode":"scenario.invalid"' <<< "$MISSING_Y1_OUTPUT"
grep -q '"message":"scenario is invalid"' <<< "$MISSING_Y1_OUTPUT"
grep -q '"fieldPath":"$.steps\[\].y1"' <<< "$MISSING_Y1_OUTPUT"

cat > "$TMPDIR/missing-x2.json" <<'JSON'
{"name":"bad","steps":[{"action":"swipe","x1":1,"y1":2,"y2":3}]}
JSON

set +e
MISSING_X2_OUTPUT="$("$ZMR" validate "$TMPDIR/missing-x2.json" --json)"
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  echo "expected validate --json to exit non-zero for a missing swipe x2 value" >&2
  exit 1
fi

grep -q '"ok":false' <<< "$MISSING_X2_OUTPUT"
grep -q '"errorCode":"scenario.invalid"' <<< "$MISSING_X2_OUTPUT"
grep -q '"message":"scenario is invalid"' <<< "$MISSING_X2_OUTPUT"
grep -q '"fieldPath":"$.steps\[\].x2"' <<< "$MISSING_X2_OUTPUT"

cat > "$TMPDIR/missing-y2.json" <<'JSON'
{"name":"bad","steps":[{"action":"swipe","x1":1,"y1":2,"x2":3}]}
JSON

set +e
MISSING_Y2_OUTPUT="$("$ZMR" validate "$TMPDIR/missing-y2.json" --json)"
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  echo "expected validate --json to exit non-zero for a missing swipe y2 value" >&2
  exit 1
fi

grep -q '"ok":false' <<< "$MISSING_Y2_OUTPUT"
grep -q '"errorCode":"scenario.invalid"' <<< "$MISSING_Y2_OUTPUT"
grep -q '"message":"scenario is invalid"' <<< "$MISSING_Y2_OUTPUT"
grep -q '"fieldPath":"$.steps\[\].y2"' <<< "$MISSING_Y2_OUTPUT"

printf '{"name":"bad","steps":[' > "$TMPDIR/malformed.json"

set +e
MALFORMED_OUTPUT="$("$ZMR" validate "$TMPDIR/malformed.json" --json)"
STATUS=$?
set -e

if [[ "$STATUS" -eq 0 ]]; then
  echo "expected validate --json to exit non-zero for malformed scenario JSON" >&2
  exit 1
fi

grep -q '"ok":false' <<< "$MALFORMED_OUTPUT"
grep -q '"errorCode":"scenario.invalid"' <<< "$MALFORMED_OUTPUT"
grep -q '"message":"malformed scenario json"' <<< "$MALFORMED_OUTPUT"
grep -q '"line":1' <<< "$MALFORMED_OUTPUT"
grep -q '"column":24' <<< "$MALFORMED_OUTPUT"

test -f "$ROOT/schemas/validate-output.schema.json"
