# ZMR iOS Shim

This directory contains the simulator-only XCTest/XCUIAutomation shim scaffold.

The public ZMR API remains the scenario file and JSON-RPC protocol. The shim
protocol is an internal local transport between the Zig runner and a simulator
test runner.

Current status:

- Zig-side command and snapshot mapping are covered in `src/ios_shim.zig`.
- `src/ios.zig` can run a configured shim command with one JSON request on
  stdin and one JSON response on stdout.
- `scripts/install-ios-shim.sh` writes an app-local `.zmr/ios-shim` command and
  copies the XCTest source files into the app repo for inclusion in a UI test
  target.
- The generated command caches `xcodebuild build-for-testing` output and runs
  selector commands through `test-without-building`, exchanging per-command
  files under `.zmr/ios-shim-state/`. Set `ZMR_IOS_SHIM_FORCE_REBUILD=1` to
  refresh the cached test bundle, or `ZMR_IOS_SHIM_ONESHOT=1` to force the
  slower one-command XCTest fallback for debugging.
- The existing iOS adapter still uses `xcrun simctl` for install, launch,
  terminate, open link, screenshots, and logs.
- Fully automated Xcode project mutation is still out of scope; users add the
  generated Swift files to their UI test target.

V1 target:

- Simulators only.
- XCTest/XCUIAutomation hierarchy snapshots mapped into `UiNode`.
- Selector actions: tap, type, erase text, hide keyboard, swipe, and home/back
  equivalent navigation.
- Clear state means uninstall and reinstall the simulator app.
