#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

if ! ruby -e 'require "xcodeproj"' >/dev/null 2>&1; then
  echo "skip: xcodeproj gem is not installed"
  exit 0
fi

"$ROOT/scripts/create-ios-demo-app.sh" \
  --out "$TMPDIR/demo-app" \
  --name ZMRDemo \
  --bundle-id com.example.mobiletest \
  --deployment-target 16.0

test -f "$TMPDIR/demo-app/ios/ZMRDemo/ZMRDemoApp.swift"
test -f "$TMPDIR/demo-app/ios/ZMRDemo/ContentView.swift"
test -f "$TMPDIR/demo-app/ios/ZMRDemo/Info.plist"
test -f "$TMPDIR/demo-app/ios/ZMRDemo.xcodeproj/project.pbxproj"
test -f "$TMPDIR/demo-app/ios/ZMRDemo.xcodeproj/xcshareddata/xcschemes/ZMRDemo.xcscheme"
test -f "$TMPDIR/demo-app/ios/ZMRDemo.xcodeproj/xcshareddata/xcschemes/ZMRDemoZMRUITests.xcscheme"
test -x "$TMPDIR/demo-app/.zmr/ios-shim"
test -x "$TMPDIR/demo-app/.zmr/ensure-ios-shim-target.sh"
test -f "$TMPDIR/demo-app/.zmr/ios-smoke.json"
test -f "$TMPDIR/demo-app/.zmr/ios-shim-smoke.json"

grep -q 'accessibilityIdentifier("continue_button")' "$TMPDIR/demo-app/ios/ZMRDemo/ContentView.swift"
grep -q 'accessibilityIdentifier("demo_input")' "$TMPDIR/demo-app/ios/ZMRDemo/ContentView.swift"
grep -q '<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>' "$TMPDIR/demo-app/ios/ZMRDemo/Info.plist"
grep -q '<string>exampleapp</string>' "$TMPDIR/demo-app/ios/ZMRDemo/Info.plist"
grep -q 'xcodebuild test-without-building' "$TMPDIR/demo-app/.zmr/ios-shim"
grep -q 'ZMR_SHIM_MODE="server"' "$TMPDIR/demo-app/.zmr/ios-shim"

ruby - "$TMPDIR/demo-app/ios/ZMRDemo.xcodeproj" <<'RUBY'
require "xcodeproj"

project = Xcodeproj::Project.open(ARGV[0])
app = project.targets.find { |target| target.name == "ZMRDemo" }
abort "missing app target" unless app
test_target = project.targets.find { |target| target.name == "ZMRDemoZMRUITests" }
abort "missing ZMR UI test target" unless test_target

app_sources = app.source_build_phase.files_references.map(&:path)
abort "missing app source" unless app_sources.include?("ZMRDemoApp.swift")
abort "missing content source" unless app_sources.include?("ContentView.swift")
abort "bad duplicated app source path" if app_sources.any? { |path| path.include?("ZMRDemo/ZMRDemo") }

app.build_configurations.each do |configuration|
  settings = configuration.build_settings
  abort "bad bundle id" unless settings["PRODUCT_BUNDLE_IDENTIFIER"] == "com.example.mobiletest"
  abort "generated plist should be disabled" unless settings["GENERATE_INFOPLIST_FILE"] == "NO"
  abort "missing app plist" unless settings["INFOPLIST_FILE"] == "ZMRDemo/Info.plist"
  abort "bad Swift version" unless settings["SWIFT_VERSION"] == "5.0"
end

shim_sources = test_target.source_build_phase.files_references.map(&:path)
abort "missing test case source" unless shim_sources.include?("../.zmr/ZMRShimUITestCase.swift")
abort "missing shim source" unless shim_sources.include?("../.zmr/shims/ios/ZMRShim.swift")
RUBY
