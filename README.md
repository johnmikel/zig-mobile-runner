# Zig Mobile Runner

Local, agent-native mobile test automation for Android first, with iOS simulator support in preview.

ZMR is a local mobile test runner designed for AI agents. It exposes typed device actions and structured observations instead of asking agents to scrape CLI output.

V1 uses Zig for orchestration, subprocess/device control, JSON-RPC, scenario execution, selector matching, wait/assertion logic, and trace generation. Android control uses ADB plus UI Automator hierarchy dumps. iOS simulator preview support uses `xcrun simctl` for lifecycle, deep links, screenshots, logs, and device discovery, with an optional local XCTest shim command for hierarchy and selector actions.

## Status

- Android is the primary supported platform.
- iOS simulator support is a preview. Lifecycle and snapshots work through `simctl`; selector-driven interaction is available when an XCTest/XCUIAutomation shim command is configured.
- Local runner only.
- AI stays outside the runner.
- JSON-RPC v1 is newline-delimited over stdio or localhost TCP.
- Runner version: `0.1.0-dev`.
- Protocol version: `2026-04-28`.
- Tested and pinned for the dev-preview release with Zig `0.15.2`.
- Zig `0.16.x` migration is a compatibility milestone because its stdlib APIs changed across filesystem, process, writer, and time surfaces used by ZMR.

This is a V1 dev preview: usable locally, covered by unit/fake-device tests, and validated against the Android pilot. It is not yet a hosted service or a broad-device certification.

## Quick Start

```bash
git clone <repo-url> zig-mobile-runner
cd zig-mobile-runner
./scripts/demo.sh
```

The demo needs no emulator, app, or credentials. It builds `zmr`, runs fake Android/iOS scenarios, exports trace bundles, and points you at the static trace viewer.
It also runs the TypeScript and Python reference clients against fake stdio ZMR servers.

## Install In An App Repo

Use the npm package when you want ZMR inside a mobile app codebase:

```bash
npm install --save-dev zig-mobile-runner
npx zmr-wizard --app-id com.example.mobiletest
npx zmr-install-android-shim --app-root . --test-package com.example.mobiletest.test --android-module android/app --gradle-file android/app/build.gradle
npx zmr-install-ios-shim --app-root . --scheme SampleUITests --workspace ios/Sample.xcworkspace --app-target SampleApp --bundle-id com.example.mobiletest --patch-xcodeproj
npx zmr doctor
```

Source or release-archive users can scaffold the same app-local `.zmr/`
workspace without npm:

```bash
zmr init --app --json --dir . --app-id com.example.mobiletest
zmr doctor --strict --json --config .zmr/config.json
```

The Android shim installer can copy the instrumentation source into the app
module and patch Gradle with the required `testInstrumentationRunner` plus
AndroidX test dependencies. If the app already declares a custom runner, the
generated shim command reuses it unless you pass `--runner` explicitly.
The iOS shim installer writes a simulator-only XCTest command that caches
`build-for-testing` output, uses `test-without-building` for selector commands,
and preserves `ZMR_IOS_SHIM_ONESHOT=1` as a cold-start debugging fallback. When
`--project` or `--workspace` plus `--app-target` are provided, it also writes
`.zmr/ensure-ios-shim-target.sh`, which uses the Ruby `xcodeproj` gem to
create/update the UI test target and shared scheme. `--workspace` resolves the
referenced project automatically when there is one project, or when exactly one
project contains `--app-target`, or when `--bundle-id` disambiguates matching
app targets; pass `--project` only for still-ambiguous workspaces.
When the shim is configured, ZMR sends single-field `tap`, `typeText`, and
`eraseText` selectors directly to XCTest instead of always resolving to
coordinates through an extra Zig snapshot. Compound selectors still use the
portable snapshot-matching fallback so behavior stays strict.

Then add scripts such as:

```json
{
  "scripts": {
    "zmr:android": "zmr run .zmr/android-smoke.json --device emulator-5554 --trace-dir traces/zmr-android",
    "zmr:ios": "zmr run .zmr/ios-smoke.json --platform ios --device booted --trace-dir traces/zmr-ios",
    "zmr:pilot": "zmr-pilot-gate --android --ios --android-app-root . --ios-app-path ./build/Debug-iphonesimulator/Sample.app --runs 20 --min-pass-rate 100 --max-failures 0"
  }
}
```

See [docs/npm.md](docs/npm.md) for npm packaging, [docs/app-integration.md](docs/app-integration.md) for app-side setup, [docs/publication.md](docs/publication.md) for public GitHub release steps, and [docs/scenario-authoring.md](docs/scenario-authoring.md) for resilient scenario patterns.
The app-local config contract is documented in [docs/config.md](docs/config.md).

For the real Sample App pilot, provide the sample app checkout and run:

```bash
./scripts/run-android-pilot.sh \
  --app-root /path/to/mobile-app \
  --device emulator-5554
```

The real pilot installs the sample app test APK, starts the test Metro environment, runs the auth and login smoke scenarios, generates reports, and writes normal plus redacted `.zmrtrace` bundles under `traces/android-app-pilot-*`.

Use `--dry-run` to inspect the exact commands without touching an emulator:

```bash
./scripts/run-android-pilot.sh --dry-run --skip-emulator --skip-metro --app-root <android-app-root>
```

For an iOS simulator demo, build a simulator `.app`, boot a simulator, then run:

```bash
./scripts/run-ios-pilot.sh \
  --app-root /path/to/mobile-app \
  --app-path /path/to/mobile-app/build/Debug-iphonesimulator/Sample.app \
  --app-id com.example.mobiletest \
  --device booted \
  --ios-shim /path/to/mobile-app/.zmr/ios-shim
```

On iOS, `clearState` means best-effort `simctl uninstall` by bundle id. If the
app is already absent, ZMR treats the simulator as clean.

See [docs/app-integration.md](docs/app-integration.md) for attaching ZMR to a mobile app codebase.

## Build And Test

Install notes are in [docs/install.md](docs/install.md).

On this macOS 26 host, Zig `0.15.2` at present fails to link the build runner with the native `aarch64-macos.26.5` target. Direct compiler commands work when targeting macOS 15:

```bash
zig test src/main.zig -target aarch64-macos.15.0
mkdir -p zig-out/bin
zig build-exe src/main.zig -target aarch64-macos.15.0 -O Debug -femit-bin=zig-out/bin/zmr
```

Coverage is gated at 90% with `kcov`:

```bash
./scripts/coverage.sh
```

Latest local run: `94.16%` line coverage, `5565/5910` lines.
On GitHub-hosted macOS runners, `coverage.sh` runs the full Zig test binary but
skips `kcov` by default because `kcov` can hang while tracing child device-tool
processes. Set `ZMR_FORCE_KCOV=1` to force the same coverage collection there.

Viewer parser tests run with Node:

```bash
node --test tests/viewer-parser.test.mjs
```

The standard build file is present for normal Zig environments:

```bash
zig build test
zig build
```

Release archives can be produced locally:

```bash
./scripts/build-release.sh
./scripts/verify-release-artifacts.sh
```

Maintainers with a Developer ID certificate can sign the generated macOS
archives and submit them for notarization before upload:

```bash
./scripts/sign-macos-release.sh --identity "Developer ID Application: Example"
./scripts/notarize-macos-release.sh --keychain-profile "zmr-notary"
./scripts/verify-release-artifacts.sh
```

The script writes `dist/*.tar.gz`, `dist/homebrew/zmr.rb`, `dist/SHA256SUMS`,
`dist/SBOM.spdx.json`, `dist/THIRD_PARTY_NOTICES.md`, and
`dist/RELEASE_MANIFEST.json`. Verify downloaded artifacts with:

```bash
cd dist
shasum -a 256 -c SHA256SUMS
```

To try the generated formula from a local release build:

```bash
brew install --build-from-source ./dist/homebrew/zmr.rb
zmr version
```

Build an npm tarball with bundled prebuilt binaries:

```bash
npm run pack:npm
```

Tagged releases build `dist/zig-mobile-runner-*.tgz`, include it in artifact
attestation, upload it with the GitHub release assets, and run
`npm publish --provenance --access public` when `NPM_TOKEN` is configured.

Run the local no-emulator demo:

```bash
./scripts/demo.sh
```

The demo builds `zmr`, lists fake Android and fake iOS simulator devices, runs one fake Android auth probe, runs one fake iOS simulator smoke flow, and writes traces under `traces/demo-*`.

Run the real Android pilot:

```bash
./scripts/run-android-pilot.sh --app-root /path/to/mobile-app --device emulator-5554
```

Pass `--adb /path/to/adb` when the Android SDK platform tools are not on
`PATH`; the same override is forwarded into the underlying `zmr run` and
benchmark calls. With `--skip-emulator`, the wrapper checks the requested
serial before installing the app and prints `zmr doctor --json` diagnostics
when setup is not ready.

For cleaner repeated runs, ZMR can create a missing AVD from an installed
system image, boot it, restore a named snapshot, wait for Android readiness,
and then run the scenario. The pilot wrapper exposes the same state controls
plus app-build setup. Add `--screen-record` when you also want a pilot-level
MP4 under the trace root:

```bash
./scripts/run-android-pilot.sh \
  --app-root /path/to/mobile-app \
  --device emulator-5554 \
  --avd Small_Phone \
  --reset-emulator \
  --restore-snapshot zmr-clean \
  --screen-record
```

Run repeated Android pilot benchmarks:

```bash
./scripts/run-android-pilot.sh \
  --app-root /path/to/mobile-app \
  --device emulator-5554 \
  --runs 20 \
  --min-pass-rate 100 \
  --max-failures 0 \
  --max-p95-ms 30000
```

Run the real iOS simulator smoke pilot:

```bash
./scripts/run-ios-pilot.sh \
  --app-path /path/to/mobile-app/build/Debug-iphonesimulator/Sample.app \
  --app-id com.example.mobiletest \
  --device booted \
  --ios-shim /path/to/mobile-app/.zmr/ios-shim
```

Run repeated iOS selector gates with the same benchmark thresholds:

```bash
./scripts/run-ios-pilot.sh \
  --app-root /path/to/mobile-app \
  --app-path /path/to/mobile-app/build/Debug-iphonesimulator/Sample.app \
  --app-id com.example.mobiletest \
  --device booted \
  --ios-shim /path/to/mobile-app/.zmr/ios-shim \
  --runs 20 \
  --min-pass-rate 100 \
  --max-failures 0 \
  --max-p95-ms 45000
```

## Troubleshooting

Use [docs/troubleshooting.md](docs/troubleshooting.md) when setup or runs fail.
Start with structured diagnostics:

```bash
zmr doctor --json
zmr validate --json .zmr/android-smoke.json
zmr explain traces/zmr-android
./scripts/release-gate.sh --dry-run
```

The troubleshooting guide covers binary resolution, scenario validation,
Android emulator state, Android shim setup, iOS simulator/shim setup, trace
inspection, release-gate failures, and `doctor --json` remediation hints.

## CLI

```bash
zmr version
zmr version --json
zmr schemas --json
zmr doctor
zmr init zmr-scenario.json --app-id com.example.mobiletest
zmr import flow-yaml ./flows/login.yaml --out .zmr/login-smoke.json --json
zmr validate examples/android-app-auth-probe.json
zmr devices --json
zmr devices --json --platform ios
zmr run --config .zmr/config.json
zmr init --app --json --dir . --app-id com.example.mobiletest
zmr run examples/android-app-auth-probe.json --device emulator-5554 --trace-dir traces/android-app-auth-probe --json
zmr run examples/android-app-auth-probe.json --android-avd Small_Phone --create-avd-if-missing --avd-system-image 'system-images;android-35;google_apis;arm64-v8a' --avd-device pixel_6 --restore-snapshot zmr-clean --wait-emulator --device emulator-5554 --trace-dir traces/android-app-auth-probe
zmr explain traces/android-app-auth-probe
zmr explain traces/android-app-auth-probe --json
zmr report traces/android-app-auth-probe --out traces/android-app-auth-probe/report.html
zmr export traces/android-app-auth-probe --out traces/android-app-auth-probe.zmrtrace
zmr run examples/ios-smoke.json --platform ios --device <sim-udid> --app-id com.example.mobiletest --trace-dir traces/ios-smoke
zmr serve --transport stdio --device emulator-5554 --app-id com.example.mobiletest --trace-dir traces/agent-session
zmr serve --transport stdio --platform ios --device <sim-udid> --app-id com.example.mobiletest --trace-dir traces/ios-agent-session
zmr serve --transport tcp --port 8765 --device emulator-5554 --app-id com.example.mobiletest --trace-dir traces/agent-session
```

`zmr validate --json` reports machine-readable authoring diagnostics for bad
scenarios, including `fieldPath`, `line`, and `column` when ZMR can identify the
source location:

```json
{"ok":false,"path":"bad.json","errorCode":"scenario.invalid","message":"scenario is invalid","fieldPath":"$.steps","line":3,"column":3}
```

Authoring guidance and templates for auth, onboarding, referral deep links, and
error states live in [docs/scenario-authoring.md](docs/scenario-authoring.md).

`zmr import flow-yaml <flow.yaml> --out .zmr/<name>.json` converts common mobile
flow YAML commands into native ZMR scenario JSON. It is a one-time migration
helper: the generated `.zmr/*.json` file is then validated, reviewed, and run
through the normal ZMR CLI. The importer intentionally supports a documented
subset of commands such as `launchApp`, `tapOn`, `inputText`, `assertVisible`,
`assertNotVisible`, `openLink`, `back`, `hideKeyboard`, `scrollUntilVisible`,
and `takeScreenshot`.

The sample app lives at:

```text
/path/to/mobile-app
```

The pilot app should be installed as `com.example.mobiletest` and started with the test Metro/environment before running the sample scenarios.

## Scenario Format

Scenarios are JSON files:

```json
{
  "name": "Sample App auth probe",
  "appId": "com.example.mobiletest",
  "steps": [
    { "action": "launch" },
    { "action": "openLink", "url": "exampleapp://e2e-auth?probe=1" },
    {
      "action": "waitVisible",
      "selector": { "text": "E2E auth probe" },
      "timeoutMs": 30000
    },
    { "action": "snapshot" }
  ]
}
```

Supported actions: `launch`, `stop`, `clearState`, `openLink`, `tap`, `typeText`, `eraseText`, `hideKeyboard`, `swipe`, `pressBack`, `waitVisible`, `waitNotVisible`, `waitAny`, `whenVisible`, `repeat`, `scrollUntilVisible`, `assertVisible`, `assertNotVisible`, `snapshot`, and `sleep`.

Any step can include `"optional": true`. Optional steps record a skipped event instead of failing the scenario.

Public JSON Schemas live in [schemas/](schemas/). The scenario schema is
[schemas/scenario.schema.json](schemas/scenario.schema.json), and setup tooling
can run `zmr schemas --json` to discover every packaged public schema. Setup
tooling can consume [schemas/schemas-output.schema.json](schemas/schemas-output.schema.json)
for the discovery response, [schemas/version-output.schema.json](schemas/version-output.schema.json)
for `zmr version --json`, [schemas/doctor-output.schema.json](schemas/doctor-output.schema.json)
for `zmr doctor --json`, [schemas/init-output.schema.json](schemas/init-output.schema.json)
for `zmr init --json` and [schemas/devices-output.schema.json](schemas/devices-output.schema.json)
for `zmr devices --json`, [schemas/validate-output.schema.json](schemas/validate-output.schema.json)
for `zmr validate --json`, [schemas/run-output.schema.json](schemas/run-output.schema.json)
for `zmr run --json`, plus [schemas/explain-output.schema.json](schemas/explain-output.schema.json)
for `zmr explain --json` and [schemas/release-manifest.schema.json](schemas/release-manifest.schema.json)
for `dist/RELEASE_MANIFEST.json`. When `zmr doctor` loads `.zmr/config.json`, it also
reports config load/type/unknown-field/empty-string errors and validates
configured `android.smokeScenario` and `ios.smokeScenario` files. Empty script
commands are rejected too, so generated package scripts cannot silently become
no-ops. In JSON mode, config warnings include `fieldPath` when ZMR can identify
the invalid key and stable `errorCode` values that setup tooling can branch on.
Device readiness checks warn with stable setup codes when ADB sees zero devices
or `xcrun` sees zero booted iOS simulators. Missing tool and shim checks also
include stable setup codes such as `setup.adb.not_found` and
`setup.android_shim.not_found`. Use `zmr doctor --strict --json` in CI or
setup scripts when any warning or missing check should fail the command.

Agent-grade control-flow examples:

```json
{
  "action": "waitAny",
  "selectors": [
    { "textContains": "Development servers" },
    { "text": "Or sign up via email here" },
    { "textContains": "Dashboard" }
  ],
  "timeoutMs": 60000
}
```

```json
{
  "action": "whenVisible",
  "selector": { "textContains": "Development servers" },
  "steps": [
    {
      "action": "tap",
      "selector": { "contentDesc": "http://10.0.2.2:8081" },
      "optional": true
    }
  ]
}
```

## Trace Output

When `--trace-dir` is provided, ZMR writes:

- `trace.json` with runner/protocol versions, scenario/app identity, terminal status, timing, event/snapshot counts, relative artifact paths, and the report path when one is generated.
- `events.jsonl` with ordered scenario/action/wait events.
- snapshot JSON with viewport size, Android display density when available, active package/activity, logs, and UI nodes.
- `artifacts/*.xml` for UI Automator hierarchy dumps.
- `artifacts/*.png` for screenshots when ADB `screencap` succeeds.
- `artifacts/screenrecord.mp4` for Android runs when `--screen-record` or `artifacts.screenRecording` is enabled.
- `artifacts/snapshot-*.json` when a scenario step explicitly requests `snapshot`.

`zmr serve --trace-dir <dir>` uses the same trace format for live JSON-RPC agent sessions. It records `rpc.request`/`rpc.response` events, domain events such as `observe.snapshot` and `ui.tap`, and lets clients export the active session with:

```json
{"jsonrpc":"2.0","id":1,"method":"trace.export","params":{"out":"traces/agent-session.zmrtrace","redact":true}}
```

Every traced run now ends with `scenario.end` carrying `status: "passed"` or `status: "failed"`. Failed runs also emit `step.error` with the failing step index and stable Zig error name before the original error is returned to the CLI. Add `--json` to `zmr run` for a terminal summary object; failed scenarios still exit non-zero after writing the summary. This gives agents a deterministic terminal record even when the process exits non-zero.

Timeout and selector failures include the last snapshot id, requested selectors, active package/activity, up to 20 visible text/content-description values, hidden exact candidates, disabled exact candidates, offscreen exact candidates, and nearest text/content-description matches from the last observed screen. Tap targets must now be visible, enabled, and inside the current viewport before ZMR will tap them.

After mutating actions, the runner asks the active device adapter to settle
instead of sleeping unconditionally. Native Android/iOS shims can wait for app
idle through their platform automation APIs; shell-only adapters keep a bounded
sleep fallback.

For native selector-capable adapters, `tap`, selector-scoped `typeText`, and
selector-scoped `eraseText` can execute as one platform command. On iOS this is
the XCTest shim fast path for single-field selectors such as `text`,
`textContains`, `resourceId`, `contentDesc`, and `className`; compound
selectors keep the portable observe-and-match path.

Use `zmr explain <trace-dir>` for a concise terminal summary of a failed run. Add `--json` for the same triage data in a stable agent-readable object. It includes scenario status, failed step, error, last diagnostic event, snapshot id, active app context, visible text, and nearest text matches.

Persisted trace JSON redacts obvious emails, bearer/JWT-like tokens, values under sensitive keys such as `password`, `token`, `secret`, `authorization`, `cookie`, and `apiKey`, plus app-specific denylisted text and resource ids from `.zmr/config.json`. Screenshots, screen recordings, and raw UI XML artifacts can still contain visual or textual secrets from the app, so public trace sharing should use `zmr export --redact`.

App-local `.zmr/config.json` can disable raw screenshot, hierarchy, and log capture, enable opt-in Android screen recording, and add app-specific redaction rules:

```json
{
  "schemaVersion": 1,
  "artifacts": {
    "screenshots": false,
    "hierarchy": false,
    "logs": false,
    "screenRecording": true
  },
  "redaction": {
    "denylistText": ["customer dob", "internal token"],
    "denylistResourceIds": ["password-field", "ssn"],
    "allowlistResourceIds": ["public-token-label"]
  }
}
```

## Reports

Generate a local HTML report from either a single trace directory or a benchmark directory containing `results.jsonl`:

```bash
zmr report traces/bench-real-20260429-auth-20 --out traces/bench-real-20260429-auth-20/report.html
zmr report traces/bench-real-20260429-login-20/zmr-1 --out traces/bench-real-20260429-login-20/zmr-1/report.html
```

Benchmark reports show pass rate, failures, mean, p95, per-run status, terminal trace status, failed step/error, and links to each run's `events.jsonl`. Single-trace reports show terminal status and an event timeline, and update `trace.json` with `reportPath`.

## Trace Bundles

Export a portable trace bundle after a run:

```bash
zmr export traces/android-app-auth-probe --out traces/android-app-auth-probe.zmrtrace
zmr export traces/android-app-auth-probe --out traces/android-app-auth-probe-redacted.zmrtrace --redact
```

`.zmrtrace` files are deterministic tar archives containing relative paths only: `trace.json`, `events.jsonl`, optional `report.html`, and `artifacts/...`.

Use `--redact` before sharing traces outside a trusted local machine. Redacted exports replace PNG screenshots with safe placeholder frames, omit screen recordings, scrub emails/tokens/sensitive JSON values from text artifacts, and annotate bundled `trace.json` with `redaction` metadata. Add `--omit-screenshots` to remove screenshot artifacts from the bundle entirely. Local trace directories are not mutated.

## Trace Viewer

Open the static viewer at [viewer/index.html](viewer/index.html), then load a `.zmrtrace` bundle. It renders run summary, event timeline, replay controls for snapshot-linked frames, payloads, side-by-side screenshots and UI trees, selectable node details, snapshot JSON, and artifact links without a backend.

## TypeScript Client

The reference client in [clients/typescript](clients/typescript) wraps ZMR's newline-delimited JSON-RPC protocol for external agents and test harnesses:

```js
import { createZmrClient } from "./clients/typescript/index.mjs";

const zmr = createZmrClient({
  command: "zmr",
  args: ["serve", "--transport", "stdio", "--device", "emulator-5554", "--app-id", "com.example.mobiletest", "--trace-dir", "traces/agent-session"],
});

try {
  await zmr.createSession();
  await zmr.openLink("exampleapp://e2e-auth?probe=1");
  await zmr.waitUntil({ text: "E2E auth probe" }, { timeoutMs: 30000 });
  const events = await zmr.traceEvents(0, { limit: 100 });
  await zmr.exportTrace("traces/agent-session-redacted.zmrtrace", { redact: true, omitScreenshots: true });
} finally {
  await zmr.close();
}
```

`runner.capabilities` exposes machine-readable protocol compatibility metadata:
`protocol.version`, `protocol.minimumCompatibleVersion`, `protocol.stability`,
and `protocol.breakingChangePolicy`. The top-level `protocolVersion` field
remains for older clients. Details are in
[docs/protocol-versioning.md](docs/protocol-versioning.md).

Long-running agents can poll `trace.events` during `zmr serve --trace-dir` to
stream redacted trace events by sequence cursor without reading trace files
directly.

## Python Client

The Python reference client in [clients/python](clients/python) provides the same stdio JSON-RPC control surface using only the Python standard library:

```python
from zmr_client import ZmrClient

with ZmrClient("zmr", ["serve", "--transport", "stdio", "--device", "emulator-5554", "--app-id", "com.example.mobiletest", "--trace-dir", "traces/agent-session"]) as zmr:
    zmr.create_session()
    zmr.open_link("exampleapp://e2e-auth?probe=1")
    zmr.wait_until({"text": "E2E auth probe"}, timeout_ms=30000)
    zmr.export_trace("traces/agent-session-redacted.zmrtrace", redact=True, omit_screenshots=True)
```

## Go Client

The Go reference client in [clients/go](clients/go) uses only the Go standard
library and drives the same stdio JSON-RPC protocol:

```go
client, err := zmr.Start(ctx, "zmr", "serve", "--transport", "stdio")
if err != nil {
    panic(err)
}
defer client.Close()

snapshot, err := client.Snapshot(ctx)
```

Run the fake-session demo:

```bash
go run ./clients/go/examples/fake-session --server tests/fake-json-rpc-server.mjs
```

## Rust Client

The Rust reference client in [clients/rust](clients/rust) provides a small
synchronous JSON-RPC wrapper around `zmr serve --transport stdio`:

```rust
let mut client = zmr_client::Client::start("zmr", ["serve", "--transport", "stdio"])?;
let snapshot = client.snapshot()?;
```

Run the fake-session demo:

```bash
cargo run --manifest-path clients/rust/Cargo.toml --example fake_session -- --server tests/fake-json-rpc-server.mjs
```

## Benchmarking

Run repeated local comparisons with:

```bash
scripts/benchmark.sh \
  --zmr examples/android-app-login-smoke.json \
  --device emulator-5554 \
  --runs 10 \
  --min-pass-rate 100 \
  --max-failures 0
```

Results are written as JSONL under `traces/bench-*`.
When threshold flags are present, `scripts/benchmark_gate.py` exits non-zero if
the recorded results miss the configured pass-rate, failure-count, mean, or p95
limits.

The Android pilot wrapper can run both pilot scenarios repeatedly and produce benchmark reports:

```bash
./scripts/run-android-pilot.sh --app-root <android-app-root> --device emulator-5554 --runs 20 --min-pass-rate 100 --max-failures 0
```

For a pre-release machine that has both app builds and real targets ready, use
the npm bin or script wrapper as the external pilot gate. When run from a
mobile app checkout, relative app paths are resolved against that checkout:

```bash
zmr-pilot-gate \
  --android --ios \
  --android-app-root <android-app-root> \
  --ios-app-path <ios-simulator-app> \
  --ios-shim ./.zmr/ios-shim
```

Run a local Android/iOS matrix from a checked-in JSON file with:

```bash
zmr-device-matrix --matrix .zmr/device-matrix.json --trace-root traces/zmr-matrix --min-pass-rate 100 --max-failures 0
```

The matrix runner writes `matrix.jsonl` plus `summary.json` under the trace
root. Each row gets its own trace directory, so failures still have normal ZMR
events, snapshots, reports, and redacted exports.

## Architecture

- `src/android.zig`: ADB-backed Android adapter.
- `src/ios.zig`: `xcrun simctl` backed iOS simulator preview adapter.
- `src/uiautomator.zig`: UI Automator XML parsing into `UiNode` values.
- `src/runner.zig`: scenario execution, selector actions, waits, assertions.
- `src/json_rpc.zig`: newline-delimited JSON-RPC 2.0 server.
- `src/report.zig`: HTML reports and terminal trace explanations.
- `src/trace.zig`: deterministic event and artifact writing.
- `src/fake_device.zig`: fake device harness for emulator-free tests.
- `clients/typescript/`: zero-dependency reference JSON-RPC client for Node/TypeScript agents.
- `clients/python/`: standard-library reference JSON-RPC client for Python agents.
- `clients/go/`: standard-library reference JSON-RPC client for Go agents.
- `clients/rust/`: synchronous reference JSON-RPC client for Rust agents.

## App Integration

Use ZMR either as a separate runner checkout or as an app-local npm dev dependency. The app provides a test APK or simulator `.app`, stable app ids, optional deep links, and accessible labels/resource ids. The runner owns device control, JSON-RPC, waits, assertions, traces, bundles, and reports. Full setup guidance is in [docs/app-integration.md](docs/app-integration.md) and [docs/npm.md](docs/npm.md).

## Next Work

The product roadmap is tracked in [docs/roadmap.md](docs/roadmap.md).

- Run the real Android/iOS pilot gates against maintained sample apps before each public release.
- Use the macOS signing helper for releases that need signed archives.

## GitHub Readiness

This repository includes:

- MIT license.
- GitHub CI and tagged-release workflows.
- Public JSON Schemas.
- App-local `.zmr/config.json` schema and CLI default loading.
- Security, contribution, trace privacy, and machine-readable protocol versioning docs.
- Static trace viewer.
- Release archive builder with SHA-256 checksums.
- Release artifact checksum verifier for archives, SBOM, notices, and Homebrew formula.
- npm package wrapper with `zmr`, `zmr-init`, and a small Node API.
- `zmr-benchmark` npm bin for repeated-run reliability gates in app repos.
- `zmr-device-matrix` npm bin for local Android/iOS matrix smoke gates.
- `zmr-pilot-gate` npm bin for the external Android+iOS pre-release pilot gate.
- Fake-device demo for credential-free evaluation.
- Real Android pilot harness for emulator-backed validation.
- Real iOS simulator smoke harness for install/open-link/screenshot trace demos.

Before publishing a tag, run `./scripts/release-gate.sh` and the external pilot
commands in [docs/shipping.md](docs/shipping.md).
