#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

if ! ruby -e 'require "xcodeproj"' >/dev/null 2>&1; then
  echo "skip: xcodeproj gem is not installed"
  exit 0
fi

APP_ROOT="$TMPDIR/app"
mkdir -p "$APP_ROOT/ios" "$APP_ROOT/.zmr/shims/ios"
cp "$ROOT/shims/ios/ZMRShim.swift" "$APP_ROOT/.zmr/shims/ios/ZMRShim.swift"
cp "$ROOT/shims/ios/ZMRShimUITestCase.swift" "$APP_ROOT/.zmr/ZMRShimUITestCase.swift"
cp "$ROOT/scripts/ensure-ios-shim-target.rb" "$APP_ROOT/.zmr/ensure-ios-shim-target.rb"
printf '<plist version="1.0"><dict></dict></plist>\n' > "$APP_ROOT/.zmr/ZMRShimUITests-Info.plist"

ruby -e '
  require "xcodeproj"
  project = Xcodeproj::Project.new(ARGV[0])
  target = project.new_target(:application, "SampleApp", :ios, "16.0")
  target.build_configurations.each do |configuration|
    configuration.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] = "com.example.mobiletest"
    configuration.build_settings["DEVELOPMENT_TEAM"] = "TEAMID1234"
  end
  project.save
' "$APP_ROOT/ios/Sample.xcodeproj"

(
  cd "$APP_ROOT"
  ruby .zmr/ensure-ios-shim-target.rb \
    --project ios/Sample.xcodeproj \
    --app-target SampleApp \
    --test-target SampleZMRUITests \
    --scheme SampleZMRUITests \
    --bundle-id com.example.mobiletest \
    --test-bundle-id com.example.mobiletest.zmr-uitests \
    --deployment-target 16.0 \
    --source .zmr/ZMRShimUITestCase.swift \
    --source .zmr/shims/ios/ZMRShim.swift \
    --info-plist .zmr/ZMRShimUITests-Info.plist
)

ruby -e '
  require "xcodeproj"
  project = Xcodeproj::Project.open(ARGV[0])
  target = project.targets.find { |candidate| candidate.name == "SampleZMRUITests" }
  abort "missing UI test target" unless target
  source_paths = target.source_build_phase.files_references.map(&:path)
  abort "missing test case source" unless source_paths.include?("../.zmr/ZMRShimUITestCase.swift")
  abort "missing shim source" unless source_paths.include?("../.zmr/shims/ios/ZMRShim.swift")
  abort "missing app dependency" unless target.dependencies.any? { |dependency| dependency.target&.name == "SampleApp" }
  target.build_configurations.each do |configuration|
    settings = configuration.build_settings
    abort "bad info plist" unless settings["INFOPLIST_FILE"] == "../.zmr/ZMRShimUITests-Info.plist"
    abort "bad bundle id" unless settings["PRODUCT_BUNDLE_IDENTIFIER"] == "com.example.mobiletest.zmr-uitests"
    abort "bad deployment target" unless settings["IPHONEOS_DEPLOYMENT_TARGET"] == "16.0"
    abort "missing test target setting" unless settings["TEST_TARGET_NAME"] == "SampleApp"
  end
' "$APP_ROOT/ios/Sample.xcodeproj"

test -f "$APP_ROOT/ios/Sample.xcodeproj/xcshareddata/xcschemes/SampleZMRUITests.xcscheme"
grep -q 'ZMRShimUITestCase/testRunZMRCommand' "$APP_ROOT/ios/Sample.xcodeproj/xcshareddata/xcschemes/SampleZMRUITests.xcscheme"
grep -q 'ZMR_SHIM_SERVER_DIR' "$APP_ROOT/ios/Sample.xcodeproj/xcshareddata/xcschemes/SampleZMRUITests.xcscheme"

WORKSPACE_APP_ROOT="$TMPDIR/workspace-app"
mkdir -p "$WORKSPACE_APP_ROOT/ios/Sample.xcworkspace"

ruby -e '
  require "xcodeproj"
  project = Xcodeproj::Project.new(ARGV[0])
  target = project.new_target(:application, "SampleApp", :ios, "16.0")
  target.build_configurations.each do |configuration|
    configuration.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] = "com.example.mobiletest"
    configuration.build_settings["DEVELOPMENT_TEAM"] = "TEAMID1234"
  end
  project.save
' "$WORKSPACE_APP_ROOT/ios/Sample.xcodeproj"

cat > "$WORKSPACE_APP_ROOT/ios/Sample.xcworkspace/contents.xcworkspacedata" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<Workspace version = "1.0">
   <FileRef location = "group:Sample.xcodeproj">
   </FileRef>
</Workspace>
XML

"$ROOT/scripts/install-ios-shim.sh" \
  --app-root "$WORKSPACE_APP_ROOT" \
  --scheme SampleZMRUITests \
  --test-target SampleZMRUITests \
  --workspace ios/Sample.xcworkspace \
  --app-target SampleApp \
  --bundle-id com.example.mobiletest \
  --test-bundle-id com.example.mobiletest.zmr-uitests \
  --deployment-target 16.0 \
  --patch-xcodeproj

(
  cd "$WORKSPACE_APP_ROOT"
  .zmr/ensure-ios-shim-target.sh
)

ruby -e '
  require "xcodeproj"
  project = Xcodeproj::Project.open(ARGV[0])
  target = project.targets.find { |candidate| candidate.name == "SampleZMRUITests" }
  abort "missing workspace-resolved UI test target" unless target
  source_paths = target.source_build_phase.files_references.map(&:path)
  abort "missing workspace-resolved test case source" unless source_paths.include?("../.zmr/ZMRShimUITestCase.swift")
  abort "missing workspace-resolved shim source" unless source_paths.include?("../.zmr/shims/ios/ZMRShim.swift")
' "$WORKSPACE_APP_ROOT/ios/Sample.xcodeproj"

MULTI_WORKSPACE_APP_ROOT="$TMPDIR/multi-workspace-app"
mkdir -p "$MULTI_WORKSPACE_APP_ROOT/ios/Sample.xcworkspace"

ruby -e '
  require "xcodeproj"
  project = Xcodeproj::Project.new(ARGV[0])
  project.new_target(:application, ARGV[1], :ios, "16.0")
  project.save
' "$MULTI_WORKSPACE_APP_ROOT/ios/Library.xcodeproj" "LibraryApp"

ruby -e '
  require "xcodeproj"
  project = Xcodeproj::Project.new(ARGV[0])
  target = project.new_target(:application, "SampleApp", :ios, "16.0")
  target.build_configurations.each do |configuration|
    configuration.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] = "com.example.mobiletest"
  end
  project.save
' "$MULTI_WORKSPACE_APP_ROOT/ios/Sample.xcodeproj"

cat > "$MULTI_WORKSPACE_APP_ROOT/ios/Sample.xcworkspace/contents.xcworkspacedata" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<Workspace version = "1.0">
   <FileRef location = "group:Library.xcodeproj">
   </FileRef>
   <FileRef location = "group:Sample.xcodeproj">
   </FileRef>
</Workspace>
XML

"$ROOT/scripts/install-ios-shim.sh" \
  --app-root "$MULTI_WORKSPACE_APP_ROOT" \
  --scheme SampleZMRUITests \
  --test-target SampleZMRUITests \
  --workspace ios/Sample.xcworkspace \
  --app-target SampleApp \
  --bundle-id com.example.mobiletest \
  --test-bundle-id com.example.mobiletest.zmr-uitests \
  --deployment-target 16.0 \
  --patch-xcodeproj

ruby -e '
  require "xcodeproj"
  sample = Xcodeproj::Project.open(ARGV[0])
  library = Xcodeproj::Project.open(ARGV[1])
  abort "missing multi-workspace UI test target" unless sample.targets.any? { |target| target.name == "SampleZMRUITests" }
  abort "patched wrong project" if library.targets.any? { |target| target.name == "SampleZMRUITests" }
' "$MULTI_WORKSPACE_APP_ROOT/ios/Sample.xcodeproj" "$MULTI_WORKSPACE_APP_ROOT/ios/Library.xcodeproj"

BUNDLE_MATCH_APP_ROOT="$TMPDIR/bundle-match-workspace-app"
mkdir -p "$BUNDLE_MATCH_APP_ROOT/ios/Sample.xcworkspace"

ruby -e '
  require "xcodeproj"
  project = Xcodeproj::Project.new(ARGV[0])
  target = project.new_target(:application, "SampleApp", :ios, "16.0")
  target.build_configurations.each do |configuration|
    configuration.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] = "com.example.other"
  end
  project.save
' "$BUNDLE_MATCH_APP_ROOT/ios/Other.xcodeproj"

ruby -e '
  require "xcodeproj"
  project = Xcodeproj::Project.new(ARGV[0])
  target = project.new_target(:application, "SampleApp", :ios, "16.0")
  target.build_configurations.each do |configuration|
    configuration.build_settings["PRODUCT_BUNDLE_IDENTIFIER"] = "com.example.mobiletest"
  end
  project.save
' "$BUNDLE_MATCH_APP_ROOT/ios/Sample.xcodeproj"

cat > "$BUNDLE_MATCH_APP_ROOT/ios/Sample.xcworkspace/contents.xcworkspacedata" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<Workspace version = "1.0">
   <FileRef location = "group:Other.xcodeproj">
   </FileRef>
   <FileRef location = "group:Sample.xcodeproj">
   </FileRef>
</Workspace>
XML

"$ROOT/scripts/install-ios-shim.sh" \
  --app-root "$BUNDLE_MATCH_APP_ROOT" \
  --scheme SampleZMRUITests \
  --test-target SampleZMRUITests \
  --workspace ios/Sample.xcworkspace \
  --app-target SampleApp \
  --bundle-id com.example.mobiletest \
  --test-bundle-id com.example.mobiletest.zmr-uitests \
  --deployment-target 16.0 \
  --patch-xcodeproj

ruby -e '
  require "xcodeproj"
  sample = Xcodeproj::Project.open(ARGV[0])
  other = Xcodeproj::Project.open(ARGV[1])
  abort "missing bundle-matched UI test target" unless sample.targets.any? { |target| target.name == "SampleZMRUITests" }
  abort "patched wrong bundle-mismatched project" if other.targets.any? { |target| target.name == "SampleZMRUITests" }
' "$BUNDLE_MATCH_APP_ROOT/ios/Sample.xcodeproj" "$BUNDLE_MATCH_APP_ROOT/ios/Other.xcodeproj"
