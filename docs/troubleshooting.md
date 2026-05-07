# Troubleshooting

Start with structured diagnostics instead of reading terminal output by hand:

```bash
zmr doctor --json
zmr doctor --strict --json
zmr validate --json .zmr/android-smoke.json
zmr explain traces/zmr-android
./scripts/release-gate.sh --dry-run
```

`zmr doctor --json` is the first command to run when setup is unclear. It
reports Zig, ADB, Android device count, `xcrun`, iOS simulator state, and
configured Android/iOS shim command paths in a machine-readable shape that
scripts and agents can inspect. Device readiness checks report `warning` when
ADB sees zero devices or `xcrun` sees zero booted iOS simulators, with stable
`setup.android.no_devices` and `setup.ios.no_booted_simulators` error codes.
Missing tool and shim checks also include stable setup codes such as
`setup.adb.not_found` and `setup.android_shim.not_found`.
By default `doctor` exits zero after printing diagnostics so interactive setup
can keep going; add `--strict` when CI or install scripts should exit non-zero
for any warning or missing check.
When run with `--config .zmr/config.json`, it
first reports whether the config file itself loaded, then validates configured
smoke scenario files from `android.smokeScenario` and
`ios.smokeScenario` so app-local setup mistakes fail before device orchestration
starts. Config files with wrong types, such as string values for boolean
artifact controls, unknown fields, such as misspelled `smokeScenario`, or empty strings
where paths/app ids/script commands are required are reported as `config` warnings.
Those warnings include `fieldPath` in JSON mode when ZMR can identify the
invalid `.zmr/config.json` key, plus stable `errorCode` values for setup
automation.
Missing scenario files are reported as `missing`; malformed scenario files are
reported as `warning` with a hint to run `zmr validate` on the configured file.
Non-`ok` checks include a `"hint"` field with the next concrete remediation
step. The JSON contract is published at
`schemas/doctor-output.schema.json`.

Top-level CLI failures use stable public error codes instead of Zig stack
traces. For example, `error[device.command_failed]: device command failed`
means a platform command such as ADB or `xcrun` failed before ZMR could collect
a device response; run `zmr doctor --json` next for setup details. An
`error[cli.unknown_command]: unknown command` response means the command name
was not recognized; run `zmr help` to inspect the supported CLI surface.

The real Android and iOS pilot wrappers run setup preflights before expensive
install or benchmark work. `scripts/run-android-pilot.sh --skip-emulator`
reports `no Android device found: <serial>` plus `setup.android.no_devices`
when the requested serial is not attached. `scripts/run-ios-pilot.sh` reports
`no booted iOS simulator found` plus `setup.ios.no_booted_simulators` when
`--device booted` has no target. In both cases the wrapper also prints the
matching `zmr doctor --json` output so CI logs contain the next remediation.

## Install Or Binary Issues

If `zmr` is not found from an app repo, check the npm wrapper resolution order:

```bash
node -e 'import("zig-mobile-runner").then(m => console.log(m.resolveBinary()))'
npx zmr version
```

The npm wrapper resolves `ZMR_BIN`, then bundled prebuilds, then
`zig-out/bin/zmr`. If none exist, install Zig and run:

```bash
npm run build:zmr
```

For source checkouts on this macOS host, use the explicit macOS 15 target shown
in the README:

```bash
zig test src/main.zig -target aarch64-macos.15.0
zig build-exe src/main.zig -target aarch64-macos.15.0 -O Debug -femit-bin=zig-out/bin/zmr
```

## Scenario Issues

Validate scenarios before touching a device:

```bash
zmr validate --json .zmr/android-smoke.json
```

The JSON output includes `errorCode`, `fieldPath`, `line`, and `column` when ZMR
can locate the source. Fix schema and selector mistakes there first; device
state debugging is slower and less reliable when the scenario itself is invalid.

## Android Device Issues

For a real emulator run, confirm that ADB sees exactly the device you intend to
use:

```bash
adb devices
zmr doctor --adb adb
```

If repeated local runs need a known state, prefer ZMR's emulator lifecycle flags
or the Android pilot wrapper:

```bash
zmr run .zmr/android-smoke.json \
  --android-avd Small_Phone \
  --create-avd-if-missing \
  --avd-system-image 'system-images;android-35;google_apis;arm64-v8a' \
  --avd-device pixel_6 \
  --restore-snapshot zmr-clean \
  --wait-emulator \
  --device emulator-5554
```

If selector actions are slow or flaky through shell/UI Automator, install the
Android shim in the app repo:

```bash
npx zmr-install-android-shim \
  --app-root . \
  --test-package com.example.mobiletest.test \
  --android-module android/app \
  --gradle-file android/app/build.gradle
```

Then run with `--android-shim ./.zmr/android-shim` or set
`tools.androidShimPath` in `.zmr/config.json`.

## iOS Simulator Issues

Confirm that `xcrun` sees a booted simulator:

```bash
xcrun simctl list devices booted
zmr doctor --xcrun xcrun
```

The simulator `.app` must be built and installed before launch/open-link flows.
On iOS, `clearState` is best-effort uninstall by bundle id; if the app is
already missing, ZMR treats the simulator as clean and continues.

Selector-grade iOS actions require an XCTest/XCUIAutomation shim command:

```bash
npx zmr-install-ios-shim \
  --app-root . \
  --scheme SampleUITests \
  --workspace ios/Sample.xcworkspace \
  --app-target SampleApp \
  --bundle-id com.example.mobiletest \
  --patch-xcodeproj
```

The generated `.zmr/ensure-ios-shim-target.sh` helper resolves the referenced
`.xcodeproj` from the workspace when there is one project, or when exactly one
project contains `--app-target`, or when `--bundle-id` disambiguates matching
app targets. Pass `--project` explicitly for still-ambiguous multi-project
workspaces. Run with `--ios-shim ./.zmr/ios-shim` or set
`tools.iosShimPath` in `.zmr/config.json`.

## Trace And Failure Issues

When a run fails, do not rerun blindly. Inspect the recorded failure:

```bash
zmr explain traces/zmr-android
zmr report traces/zmr-android --out traces/zmr-android/report.html
```

Timeout diagnostics include the active package/activity, visible text, hidden or
disabled exact selector candidates, offscreen candidates, and nearest text
matches from the last snapshot. Redacted bundles replace PNG screenshots with
placeholder frames and omit screen recordings, so use them for sharing:

```bash
zmr export traces/zmr-android --out traces/zmr-android-redacted.zmrtrace --redact
```

## Release Gate Issues

To see exactly what the local release gate will run:

```bash
./scripts/release-gate.sh --dry-run
```

The gate intentionally prints real Android and iOS pilot commands at the end
instead of running them by default. Those pilots need app builds and devices, so
run them explicitly before publishing reliability or performance claims. Use
`zmr-pilot-gate --dry-run` with the same app path flags from an app repo or
release machine to inspect the combined Android+iOS external gate command
before starting the real runs.
