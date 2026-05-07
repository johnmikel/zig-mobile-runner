#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

ZMR="$ROOT/zig-out/bin/zmr"
test -x "$ZMR"

"$ZMR" init --app --dir "$TMPDIR/app" --app-id com.example.bootstrap > "$TMPDIR/init.out"

grep -q 'created .*/.zmr/config.json' "$TMPDIR/init.out"
grep -q 'next: zmr doctor --strict --json --config .*/.zmr/config.json' "$TMPDIR/init.out"
test -f "$TMPDIR/app/.zmr/config.json"
test -f "$TMPDIR/app/.zmr/android-smoke.json"
test -f "$TMPDIR/app/.zmr/ios-smoke.json"
grep -q 'traces/' "$TMPDIR/app/.gitignore"
grep -q '"appId": "com.example.bootstrap"' "$TMPDIR/app/.zmr/config.json"
grep -q '"doctor": "zmr doctor --strict --json --config .zmr/config.json"' "$TMPDIR/app/.zmr/config.json"

"$ZMR" init --app --json --dir "$TMPDIR/json-app" --app-id com.example.json > "$TMPDIR/init.json"
grep -q '"ok":true' "$TMPDIR/init.json"
grep -q '"mode":"app"' "$TMPDIR/init.json"
grep -q '"appId":"com.example.json"' "$TMPDIR/init.json"
grep -q '"created":\[' "$TMPDIR/init.json"
grep -q '"next":"zmr doctor --strict --json --config '"$TMPDIR"'/json-app/.zmr/config.json"' "$TMPDIR/init.json"
test -f "$TMPDIR/json-app/.zmr/config.json"

"$ZMR" init "$TMPDIR/single-scenario.json" --app-id com.example.single --json > "$TMPDIR/init-scenario.json"
grep -q '"ok":true' "$TMPDIR/init-scenario.json"
grep -q '"mode":"scenario"' "$TMPDIR/init-scenario.json"
grep -q '"created":\["'"$TMPDIR"'/single-scenario.json"\]' "$TMPDIR/init-scenario.json"
"$ZMR" validate "$TMPDIR/single-scenario.json"

(
  cd "$TMPDIR/app"
  "$ZMR" validate .zmr/android-smoke.json
  "$ZMR" validate .zmr/ios-smoke.json
  "$ZMR" doctor --strict --json \
    --config .zmr/config.json \
    --adb "$ROOT/tests/fake-adb.sh" \
    --xcrun "$ROOT/tests/fake-xcrun.sh" > "$TMPDIR/doctor.json"
)

grep -q '"ok":true' "$TMPDIR/doctor.json"
grep -q '"name":"android-smoke-scenario"' "$TMPDIR/doctor.json"
grep -q '"name":"ios-smoke-scenario"' "$TMPDIR/doctor.json"

if "$ZMR" init --app --dir "$TMPDIR/app" --app-id com.example.other > "$TMPDIR/init-again.out" 2>&1; then
  echo "expected app init to protect existing .zmr files without --force" >&2
  exit 1
fi

"$ZMR" init --app --dir "$TMPDIR/app" --app-id com.example.other --force > "$TMPDIR/init-force.out"
grep -q '"appId": "com.example.other"' "$TMPDIR/app/.zmr/config.json"
