#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

output="$("$ROOT/scripts/demo-ios-real.sh" \
  --dry-run \
  --out "$TMPDIR/demo-ios" \
  --device fake-ios-1 \
  --app-id com.example.mobiletest \
  --runs 3 \
  --trace-root "$TMPDIR/traces" 2>&1)"

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
assert "scripts/run-ios-pilot.sh" in output
assert "--app-path" in output
assert "DerivedData/Build/Products/Debug-iphonesimulator/ZMRDemo.app" in output
assert "--device fake-ios-1" in output
assert "--ios-shim" in output
assert "--runs 3" in output
assert f"--trace-root {tmp}/traces" in output
PY
