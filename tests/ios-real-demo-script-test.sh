#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

for args in "--out" "--name" "--app-id" "--device" "--deployment-target" "--runs" "--trace-root" "--xcrun"; do
  set +e
  missing_value_output="$("$ROOT/scripts/demo-ios-real.sh" $args 2>&1)"
  missing_value_status=$?
  set -e
  if [[ "$missing_value_status" -ne 2 ]]; then
    echo "demo-ios-real should exit 2 for missing value: $args" >&2
    exit 1
  fi
  grep -q -- "$args requires a value" <<< "$missing_value_output"
done

output="$("$ROOT/scripts/demo-ios-real.sh" \
  --dry-run \
  --out "$TMPDIR/demo-ios" \
  --device booted \
  --app-id com.example.mobiletest \
  --runs 3 \
  --trace-root "$TMPDIR/traces" \
  --cleanup-build-products 2>&1)"

python3 - "$output" "$TMPDIR" <<'PY'
import sys

output = sys.argv[1]
tmp = sys.argv[2]

assert "DRY RUN" in output
assert "create-ios-demo-app.sh --out" in output
assert f"{tmp}/demo-ios" in output
assert "xcodebuild -project" in output
assert "ios/ZMRDemo.xcodeproj" in output
assert "-scheme ZMRDemo" in output
assert "-derivedDataPath" in output
assert "xcrun simctl list devices booted" in output
assert "auto boot first available iOS simulator when no simulator is booted" in output
assert "try available iOS simulators until one boots" in output
assert "xcrun simctl bootstatus booted -b" in output
assert "scripts/run-ios-pilot.sh" in output
assert "--app-path" in output
assert "DerivedData/Build/Products/Debug-iphonesimulator/ZMRDemo.app" in output
assert "--device booted" in output
assert "--ios-shim" in output
assert "--runs 3" in output
assert f"--trace-root {tmp}/traces" in output
assert f"rm -rf {tmp}/demo-ios/DerivedData" in output
PY
