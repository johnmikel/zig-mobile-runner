#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

ZMR="$ROOT/zig-out/bin/zmr"
test -x "$ZMR"

EMPTY_ADB="$TMPDIR/fake-adb-empty.sh"
EMPTY_XCRUN="$TMPDIR/fake-xcrun-empty.sh"

cat > "$EMPTY_ADB" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  version) printf 'Android Debug Bridge version 1.0.41\n' ;;
  devices) printf 'List of devices attached\n' ;;
  *) exit 2 ;;
esac
SH

cat > "$EMPTY_XCRUN" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--version" ]]; then
  printf 'xcrun version 70\n'
  exit 0
fi
if [[ "${1:-}" == "simctl" && "${2:-}" == "list" && "${3:-}" == "devices" && "${4:-}" == "--json" ]]; then
  printf '{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-18-5":[]}}\n'
  exit 0
fi
exit 2
SH

chmod +x "$EMPTY_ADB" "$EMPTY_XCRUN"

JSON_OUTPUT="$("$ZMR" doctor --json --adb "$EMPTY_ADB" --xcrun "$EMPTY_XCRUN")"
grep -q '"ok":false' <<< "$JSON_OUTPUT"
grep -q '"errorCode":"setup.android.no_devices"' <<< "$JSON_OUTPUT"
grep -q '"errorCode":"setup.ios.no_booted_simulators"' <<< "$JSON_OUTPUT"

if "$ZMR" doctor --strict --json --adb "$EMPTY_ADB" --xcrun "$EMPTY_XCRUN" > "$TMPDIR/strict.json"; then
  echo "expected doctor --strict to exit non-zero for warning checks" >&2
  exit 1
fi
grep -q '"ok":false' "$TMPDIR/strict.json"

"$ZMR" doctor --strict --json \
  --adb "$ROOT/tests/fake-adb.sh" \
  --xcrun "$ROOT/tests/fake-xcrun.sh" \
  --android-shim "$ROOT/tests/fake-android-shim.sh" \
  --ios-shim "$ROOT/tests/fake-ios-shim.sh" > "$TMPDIR/healthy.json"
grep -q '"ok":true' "$TMPDIR/healthy.json"
