#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

"$ROOT/scripts/install-ios-shim.sh" \
  --app-root "$TMPDIR/app" \
  --scheme SampleUITests \
  --app-target SampleApp \
  --project ios/Sample.xcodeproj \
  --derived-data-path ios/build/ZMRDerivedData \
  --bundle-id com.example.mobiletest \
  --test-bundle-id com.example.mobiletest.zmr-uitests \
  --deployment-target 16.0 \
  --device booted

test -x "$TMPDIR/app/.zmr/ios-shim"
test -f "$TMPDIR/app/.zmr/ZMRShimUITestCase.swift"
test -f "$TMPDIR/app/.zmr/ZMRShimUITests-Info.plist"
bash -n "$TMPDIR/app/.zmr/ios-shim"

grep -q 'xcodebuild test' "$TMPDIR/app/.zmr/ios-shim"
grep -q 'cd "'"$TMPDIR/app"'"' "$TMPDIR/app/.zmr/ios-shim"
grep -q -- '-project "ios/Sample.xcodeproj"' "$TMPDIR/app/.zmr/ios-shim"
grep -q -- '-derivedDataPath "ios/build/ZMRDerivedData"' "$TMPDIR/app/.zmr/ios-shim"
grep -q 'ZMR_SHIM_REQUEST_FILE' "$TMPDIR/app/.zmr/ios-shim"
grep -q 'ZMR_SHIM_RESPONSE_FILE' "$TMPDIR/app/.zmr/ios-shim"
grep -q 'ZMR_IOS_SHIM_ONESHOT' "$TMPDIR/app/.zmr/ios-shim"
grep -q 'ios-shim-state' "$TMPDIR/app/.zmr/ios-shim"
grep -q 'PID_FILE="$STATE_DIR/xcodebuild.pid"' "$TMPDIR/app/.zmr/ios-shim"
grep -q 'READY_FILE="$SERVER_DIR/ready"' "$TMPDIR/app/.zmr/ios-shim"
grep -q 'BUILD_READY_FILE="$STATE_DIR/build-for-testing.ready"' "$TMPDIR/app/.zmr/ios-shim"
grep -q 'ZMR_IOS_SHIM_FORCE_REBUILD' "$TMPDIR/app/.zmr/ios-shim"
grep -q 'request-$REQUEST_ID.json' "$TMPDIR/app/.zmr/ios-shim"
grep -q 'response-$REQUEST_ID.json' "$TMPDIR/app/.zmr/ios-shim"
grep -q 'ZMR_SHIM_MODE="server"' "$TMPDIR/app/.zmr/ios-shim"
grep -q 'ZMR_SHIM_SERVER_DIR="$SERVER_DIR"' "$TMPDIR/app/.zmr/ios-shim"
grep -q 'xcodebuild build-for-testing' "$TMPDIR/app/.zmr/ios-shim"
grep -q 'nohup xcodebuild test-without-building' "$TMPDIR/app/.zmr/ios-shim"
grep -q '< /dev/null' "$TMPDIR/app/.zmr/ios-shim"
grep -q 'tail -120 "$LOG_FILE"' "$TMPDIR/app/.zmr/ios-shim"
grep -q 'SampleUITests' "$TMPDIR/app/.zmr/ios-shim"
grep -q 'com.example.mobiletest' "$TMPDIR/app/.zmr/ios-shim"
test -x "$TMPDIR/app/.zmr/ensure-ios-shim-target.sh"
test -f "$TMPDIR/app/.zmr/ensure-ios-shim-target.rb"
bash -n "$TMPDIR/app/.zmr/ensure-ios-shim-target.sh"
ruby -c "$TMPDIR/app/.zmr/ensure-ios-shim-target.rb" >/dev/null
grep -q 'PROJECT=ios/Sample.xcodeproj' "$TMPDIR/app/.zmr/ensure-ios-shim-target.sh"
grep -q 'APP_TARGET=SampleApp' "$TMPDIR/app/.zmr/ensure-ios-shim-target.sh"
grep -q 'TEST_TARGET=SampleUITests' "$TMPDIR/app/.zmr/ensure-ios-shim-target.sh"
grep -q 'SCHEME=SampleUITests' "$TMPDIR/app/.zmr/ensure-ios-shim-target.sh"
grep -q 'BUNDLE_ID=com.example.mobiletest' "$TMPDIR/app/.zmr/ensure-ios-shim-target.sh"
grep -q 'TEST_BUNDLE_ID=com.example.mobiletest.zmr-uitests' "$TMPDIR/app/.zmr/ensure-ios-shim-target.sh"
grep -q 'DEPLOYMENT_TARGET=16.0' "$TMPDIR/app/.zmr/ensure-ios-shim-target.sh"
grep -q -- '--project "$PROJECT"' "$TMPDIR/app/.zmr/ensure-ios-shim-target.sh"
grep -q -- '--app-target "$APP_TARGET"' "$TMPDIR/app/.zmr/ensure-ios-shim-target.sh"
grep -q 'xcodeproj' "$TMPDIR/app/.zmr/ios-shim.README.md"
grep -q 'ensure-ios-shim-target.sh' "$TMPDIR/app/.zmr/ios-shim.README.md"
grep -q 'testRunZMRCommand' "$TMPDIR/app/.zmr/ZMRShimUITestCase.swift"
grep -q 'XCUIApplication' "$TMPDIR/app/.zmr/ZMRShimUITestCase.swift"
grep -q 'InfoDictionaryKey' "$TMPDIR/app/.zmr/ZMRShimUITestCase.swift"
grep -q 'runServer' "$TMPDIR/app/.zmr/ZMRShimUITestCase.swift"
grep -q 'process(requestAt requestFile:' "$TMPDIR/app/.zmr/ZMRShimUITestCase.swift"
grep -q 'ZMR_SHIM_MODE' "$TMPDIR/app/.zmr/ZMRShimUITestCase.swift"
grep -q 'ZMR_SHIM_SERVER_DIR' "$TMPDIR/app/.zmr/ZMRShimUITestCase.swift"
grep -q 'resolveElement(selector:' "$TMPDIR/app/.zmr/ZMRShimUITestCase.swift"
grep -q 'matches(selector:' "$TMPDIR/app/.zmr/ZMRShimUITestCase.swift"
grep -q 'command.selector' "$TMPDIR/app/.zmr/ZMRShimUITestCase.swift"
grep -q 'selector.unsupported' "$TMPDIR/app/.zmr/ZMRShimUITestCase.swift"
grep -q 'ZMR_SHIM_REQUEST_FILE' "$TMPDIR/app/.zmr/ZMRShimUITests-Info.plist"
grep -q 'ZMR_SHIM_MODE' "$TMPDIR/app/.zmr/ZMRShimUITests-Info.plist"
grep -q 'ZMR_SHIM_SERVER_DIR' "$TMPDIR/app/.zmr/ZMRShimUITests-Info.plist"
