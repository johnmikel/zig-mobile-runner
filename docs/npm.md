# npm Package

ZMR can be installed in a mobile app codebase as a dev dependency:

```bash
npm install --save-dev zig-mobile-runner
```

The package exposes:

- `zmr`: CLI binary wrapper.
- `zmr-init`: app-local scenario scaffolder.
- `zmr-wizard`: guided setup and dependency checker.
- `zmr-benchmark`: repeated-run wrapper with pass-rate and duration gates.
- `zmr-benchmark-command`: repeated-run wrapper for app-local baseline commands
  so existing runner flows can be compared without custom glue.
- `zmr-compare-benchmarks`: generic comparison report for ZMR and app-local
  baseline benchmark rows.
- `zmr-device-matrix`: local multi-device Android/iOS matrix runner with
  pass-rate gates.
- `zmr-pilot-gate`: external release pilot gate that delegates to the Android
  and iOS app pilot wrappers on machines with real targets.
- `zmr-install-android-shim`: writes the app-local Android instrumentation
  shim command and source file.
- `zmr-install-ios-shim`: writes the app-local iOS XCTest shim command and
  source files.
- `zmr-create-ios-demo-app`: creates a generic SwiftUI simulator app with
  `.zmr/` scenarios and the iOS shim already installed for public demos.
- `zmr-demo-ios`: creates, builds, and runs the generated iOS simulator demo
  through the real iOS pilot wrapper.
- `import { runZmr, spawnZmr, resolveBinary } from "zig-mobile-runner"` for Node scripts.

## App Setup

From the app repo:

```bash
npx zmr-wizard --app-id com.example.mobiletest
```

This creates:

```text
.zmr/
  config.json
  android-smoke.json
  ios-smoke.json
```

`.zmr/config.json` is the app-local source of truth for default devices, trace directories, smoke scenario paths, and suggested script commands. ZMR auto-discovers it from the app repo, and explicit CLI flags override it. The wizard does not inspect or depend on any other mobile test runner configuration.

Add app-local scripts:

```json
{
  "scripts": {
    "zmr:doctor": "zmr doctor",
    "zmr:android": "zmr run .zmr/android-smoke.json --device emulator-5554 --trace-dir traces/zmr-android",
    "zmr:android:reliability": "ZMR_BIN=${ZMR_BIN:-zmr} zmr-benchmark --zmr .zmr/android-smoke.json --device emulator-5554 --app-id com.example.mobiletest --runs 20 --trace-root traces/zmr-android-reliability --min-pass-rate 100 --max-failures 0 --max-p95-ms 30000 && zmr report traces/zmr-android-reliability --out traces/zmr-android-reliability/report.html",
    "zmr:matrix": "ZMR_BIN=${ZMR_BIN:-zmr} zmr-device-matrix --matrix .zmr/device-matrix.json --trace-root traces/zmr-matrix --min-pass-rate 100 --max-failures 0",
    "zmr:ios": "zmr run .zmr/ios-smoke.json --platform ios --device booted --trace-dir traces/zmr-ios",
    "zmr:ios:reliability": "ZMR_BIN=${ZMR_BIN:-zmr} zmr-benchmark --zmr .zmr/ios-smoke.json --platform ios --device booted --app-id com.example.mobiletest --xcrun xcrun --runs 20 --trace-root traces/zmr-ios-reliability --min-pass-rate 100 --max-failures 0 --max-p95-ms 45000 && zmr report traces/zmr-ios-reliability --out traces/zmr-ios-reliability/report.html",
    "zmr:pilot": "zmr-pilot-gate --android --ios --android-app-root . --ios-app-path ./build/Debug-iphonesimulator/Sample.app --runs 20 --min-pass-rate 100 --max-failures 0",
    "zmr:serve": "zmr serve --transport stdio --device emulator-5554 --app-id com.example.mobiletest --trace-dir traces/zmr-agent"
  }
}
```

For non-interactive CI or template setup:

```bash
npx zmr-wizard \
  --yes \
  --app-id com.example.mobiletest \
  --android \
  --android-shim ./.zmr/android-shim \
  --ios \
  --ios-shim ./.zmr/ios-shim \
  --package-json
```

The wizard checks Node, ZMR, ADB, `xcrun`, and Zig when applicable. It scaffolds `.zmr` scenarios and can patch `package.json` scripts.
It also ensures `traces/` is ignored in the app repo.
The reliability scripts use `zmr-benchmark` with `100%` pass-rate and zero-failure
defaults; tune p95 thresholds only after capturing stable local baseline runs.
For release validation, `zmr-pilot-gate` is safe to run from the app checkout:
relative app roots, APK paths, simulator app paths, shim paths, and trace roots
are resolved against the current app directory before the packaged runner
scripts are invoked.

The standalone CLI has the same non-interactive app-local bootstrap for
source or release-archive installs:

```bash
zmr init --app --json --dir . --app-id com.example.mobiletest
zmr doctor --strict --json --config .zmr/config.json
```

Omit `--android-shim` or `--ios-shim` for shell/screenshot-only smoke runs.
Include them when the app repo provides native shim commands for faster
hierarchy and selector actions.

## iOS Demo App

For a clean public iOS demo that does not depend on a private app:

```bash
npx zmr-demo-ios --out /tmp/zmr-ios-demo --device booted
```

That command creates the demo app, builds it with Xcode, runs the iOS pilot, and
writes trace reports plus redacted bundles. To inspect or customize the app
before running the pilot manually:

```bash
npx zmr-create-ios-demo-app --out /tmp/zmr-ios-demo
cd /tmp/zmr-ios-demo
xcodebuild -project ios/ZMRDemo.xcodeproj -scheme ZMRDemo -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData build
```

Then boot a simulator and run the pilot wrapper from a ZMR checkout:

```bash
scripts/run-ios-pilot.sh \
  --app-root /tmp/zmr-ios-demo \
  --app-path /tmp/zmr-ios-demo/DerivedData/Build/Products/Debug-iphonesimulator/ZMRDemo.app \
  --app-id com.example.mobiletest \
  --device booted \
  --ios-shim /tmp/zmr-ios-demo/.zmr/ios-shim
```

To scaffold the Android shim command into an app repo:

```bash
npx zmr-install-android-shim \
  --app-root . \
  --test-package com.example.mobiletest.test \
  --runner androidx.test.runner.AndroidJUnitRunner \
  --android-module android/app \
  --gradle-file android/app/build.gradle
```

`--android-module` copies the shim into
`android/app/src/androidTest/java/dev/zmr/shim/ZMRShimInstrumentedTest.java`.
`--gradle-file` appends guarded Gradle blocks for `testInstrumentationRunner`,
AndroidX Test runner, JUnit extension, and UI Automator. If the Gradle file
already has a custom `testInstrumentationRunner` and `--runner` is omitted, the
generated `.zmr/android-shim` command uses that runner. Run ZMR with
`--android-shim ./.zmr/android-shim`.

To scaffold the iOS shim command into an app repo:

```bash
npx zmr-install-ios-shim \
  --app-root . \
  --scheme SampleUITests \
  --test-target SampleUITests \
  --workspace ios/Sample.xcworkspace \
  --app-target SampleApp \
  --derived-data-path ios/build/ZMRDerivedData \
  --bundle-id com.example.mobiletest \
  --patch-xcodeproj
```

The installer writes:

- `.zmr/ios-shim`
- `.zmr/ensure-ios-shim-target.sh`
- `.zmr/ensure-ios-shim-target.rb`
- `.zmr/ZMRShimUITestCase.swift`
- `.zmr/shims/ios/ZMRShim.swift`
- `.zmr/ZMRShimUITests-Info.plist`

Run `.zmr/ensure-ios-shim-target.sh` to create/update the UI test target, add
the Swift files, configure the generated Info.plist, and write a shared scheme.
The helper uses the Ruby `xcodeproj` gem. With `--workspace`, it resolves the
referenced `.xcodeproj` automatically when there is one project, or when exactly
one project contains `--app-target`, or when `--bundle-id` disambiguates
matching app targets. Pass `--project ios/Sample.xcodeproj` explicitly for
still-ambiguous multi-project workspaces or project-only apps.

Run ZMR with `--ios-shim ./.zmr/ios-shim`.
The generated command caches `build-for-testing` output under
`.zmr/ios-shim-state/`, uses `test-without-building` for selector commands, and
prints the last Xcode log lines when XCTest fails. Set
`ZMR_IOS_SHIM_FORCE_REBUILD=1` after app-side target changes, or
`ZMR_IOS_SHIM_ONESHOT=1` for a cold-start fallback while debugging app-side Xcode
wiring.

## Native Binary Resolution

The npm wrapper resolves `zmr` in this order:

1. `ZMR_BIN=/path/to/zmr`
2. bundled `prebuilds/<platform>-<arch>/zmr`
3. local source build at `zig-out/bin/zmr`

If no binary is found, install Zig and run:

```bash
npm run build:zmr
```

For release publishing, build npm tarballs with:

```bash
npm run pack:npm
```

That command builds release binaries, copies them into `prebuilds/`, and runs `npm pack`.

## Node API

```js
import { runZmr } from "zig-mobile-runner";

await runZmr([
  "run",
  "--config",
  ".zmr/config.json",
]);
```

Use the CLI for normal app scripts and the JS API for custom toolchains or agent orchestration.
