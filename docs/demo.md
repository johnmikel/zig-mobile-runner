# Demo

Run the local demo with no emulator, simulator, app, or credentials:

```bash
./scripts/demo.sh
```

The script builds `zig-out/bin/zmr`, then runs:

- `zmr version`
- `zmr version --json`
- `zmr schemas --json`
- `zmr validate examples/demo-fake.json`
- `zmr validate examples/demo-failure.json`
- `zmr validate examples/android-app-onboarding.json`
- `zmr validate examples/android-app-referral-deep-link.json`
- `zmr validate examples/android-app-error-state.json`
- `zmr validate examples/android-shim-smoke.json`
- `zmr validate examples/ios-smoke.json`
- `zmr validate examples/ios-shim-smoke.json`
- expected-failing `zmr validate --json` output that shows `fieldPath`, `line`,
  and `column` for invalid scenarios covered by `schemas/validate-output.schema.json`
- `zmr doctor --adb ./tests/fake-adb.sh --xcrun ./tests/fake-xcrun.sh --ios-shim ./tests/fake-ios-shim.sh`
- `zmr doctor --json` output for a missing Android shim that includes a
  remediation `hint`
- `zmr doctor --json` output that warns with stable setup `errorCode` values
  when no Android devices or booted iOS simulators are ready
- expected-failing `zmr doctor --strict --json` output for the same no-device
  setup, showing how CI can fail without parsing the diagnostics itself
- `zmr doctor --json --config traces/demo-doctor-config.json` output that
  validates configured smoke scenario files, including an `ios-smoke-scenario` remediation
  for a bad `ios.smokeScenario` and a `zmr validate on the configured Android
  smoke scenario` hint for malformed scenario JSON
- `zmr doctor --json --config traces/demo-bad-config.json` output that reports
  stable `errorCode` plus `fieldPath` for an invalid app-local config value
  before device setup starts
- `zmr devices --adb ./tests/fake-adb.sh`
- `zmr devices --json --adb ./tests/fake-adb.sh`
- `zmr devices --platform ios --xcrun ./tests/fake-xcrun.sh`
- `zmr devices --json --platform ios --xcrun ./tests/fake-xcrun.sh`
- `zmr init --app --json --dir traces/demo-init-app --app-id com.example.demoapp`
  followed by validation and strict config-driven doctor checks from that
  generated app-local workspace
- `zmr import flow-yaml traces/demo-flow-yaml-flow.yaml --out traces/demo-imported-flow.json --json`
  followed by validation of the generated native ZMR scenario
- `zmr run examples/demo-fake.json --trace-dir traces/demo-fake-android --json`
- `zmr run examples/demo-failure.json --trace-dir traces/demo-failure --json`
- `zmr explain traces/demo-failure`
- `zmr explain traces/demo-failure --json`
- `zmr serve --transport stdio --trace-dir traces/demo-rpc-session`
- `node clients/typescript/examples/fake-session.mjs`
- `python3 clients/python/examples/fake_session.py`
- `zmr run examples/ios-smoke.json --platform ios --trace-dir traces/demo-fake-ios`

The fake Android flow exercises selector matching and wait/assert trace output.
The fake failure flow exercises failed trace diagnostics and the terminal
`zmr explain` summary.
The fake JSON-RPC flow exercises the agent protocol over stdio, live RPC trace
recording, `observe.snapshot`, and redacted `trace.export`.
Doctor output is intentionally structured for setup automation; `--json`
includes remediation `hint` values for missing or warning checks, and
`--config` validates app-local smoke scenario files. Add `--strict` when a
non-`ok` diagnostic should also make the command fail.
The TypeScript reference client flow exercises the same protocol through the
client API external agents would use.
The Python reference client flow verifies the same agent integration path with
only the Python standard library.
The fake Android shim flow exercises shim-backed hierarchy, wait, tap, type,
hide-keyboard, and snapshot handling.
The fake iOS flow exercises simulator lifecycle, deep-link opening, screenshot
artifact capture, log capture, and snapshot trace writing. The fake iOS shim
flow exercises shim-backed hierarchy, wait, tap, type, hide-keyboard, and
snapshot handling.

Load any generated `.zmrtrace` in `viewer/index.html` to inspect the replay
timeline, payloads, screenshot, UI tree, selected node details, and raw
artifacts side-by-side.

## Real Android Pilot Demo

Run the Android pilot against a sample app test build:

```bash
./scripts/run-android-pilot.sh \
  --app-root /path/to/mobile-app \
  --device emulator-5554
```

To force a known emulator state, direct `zmr run` supports `--android-avd`,
`--create-avd-if-missing`, `--avd-system-image`, `--avd-device`,
`--restore-snapshot`, `--reset-emulator`, and `--wait-emulator`. The pilot
wrapper accepts the same state controls while also building/installing the app.
Add `--screen-record` to keep a pilot-level MP4 under the trace root:

```bash
./scripts/run-android-pilot.sh \
  --app-root /path/to/mobile-app \
  --device emulator-5554 \
  --avd Small_Phone \
  --reset-emulator \
  --restore-snapshot zmr-clean \
  --screen-record
```

The script builds `zmr` when needed, validates both sample scenarios, installs the debug test APK, starts the app's test Metro server, and runs:

- `examples/android-app-auth-probe.json`
- `examples/android-app-login-smoke.json`

For each single run it writes:

- `auth/report.html`
- `login-smoke/report.html`
- `auth.zmrtrace`
- `auth-redacted.zmrtrace`
- `login-smoke.zmrtrace`
- `login-smoke-redacted.zmrtrace`
- `screenrecord.mp4` when pilot `--screen-record`, `zmr run --screen-record`, or `.zmr/config.json` `artifacts.screenRecording` is enabled

Use the redacted bundles for demos outside a trusted local machine:

```bash
open viewer/index.html
```

Then load `auth-redacted.zmrtrace` or `login-smoke-redacted.zmrtrace`.

Inspect the command plan without touching the emulator:

```bash
./scripts/run-android-pilot.sh --dry-run --skip-emulator --skip-metro --app-root <android-app-root>
```

Run repeated benchmark passes:

```bash
./scripts/run-android-pilot.sh \
  --app-root <android-app-root> \
  --device emulator-5554 \
  --runs 20 \
  --min-pass-rate 100 \
  --max-failures 0
```

`<trace-root>/metro.log` may contain sensitive app output from the sample app test environment. Do not publish raw Metro logs.

## Real iOS Simulator Demo

Build the app for an iOS simulator, boot a simulator, then run:

```bash
./scripts/run-ios-pilot.sh \
  --app-root /path/to/mobile-app \
  --app-path /path/to/mobile-app/build/Debug-iphonesimulator/Sample.app \
  --app-id com.example.mobiletest \
  --device booted \
  --ios-shim /path/to/mobile-app/.zmr/ios-shim
```

For each run it writes:

- `ios-smoke/report.html`
- `ios-smoke.zmrtrace`
- `ios-smoke-redacted.zmrtrace`
- `ios-shim-smoke/report.html` when `--ios-shim` is set
- `ios-shim-smoke.zmrtrace` when `--ios-shim` is set
- `ios-shim-smoke-redacted.zmrtrace` when `--ios-shim` is set

The iOS demo covers simulator install, launch/open-link, screenshot capture,
log capture, trace export, and viewer inspection. With `--ios-shim`, it also
runs `examples/ios-shim-smoke.json`, which exercises launch, openLink,
waitVisible, tap, typeText, hideKeyboard, and snapshot through the generated
XCTest/XCUIAutomation shim command.

`clearState` on iOS is best-effort app uninstall by bundle id. Repeating it is
safe: a simulator where the app is already absent is treated as clean.
