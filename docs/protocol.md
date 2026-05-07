# ZMR JSON-RPC Protocol

ZMR exposes newline-delimited JSON-RPC 2.0 over stdio or localhost TCP in v1. Each request is one JSON object followed by `\n`. Each response is one JSON object followed by `\n`.

Current runner version: `0.1.0-dev`.

Current protocol version: `2026-04-28`.

Public schemas:

- `schemas/json-rpc.schema.json`
- `schemas/scenario.schema.json`
- `schemas/snapshot.schema.json`
- `schemas/action-result.schema.json`
- `schemas/trace-event.schema.json`
- `schemas/trace-manifest.schema.json`
- `schemas/doctor-output.schema.json`
- `schemas/init-output.schema.json`
- `schemas/import-output.schema.json`
- `schemas/devices-output.schema.json`
- `schemas/validate-output.schema.json`
- `schemas/version-output.schema.json`
- `schemas/explain-output.schema.json`
- `schemas/run-output.schema.json`
- `schemas/release-manifest.schema.json`
- `schemas/schemas-output.schema.json`

Compatibility fixtures live under `docs/protocol-fixtures/`. The Zig unit suite
loads these JSONL requests and asserts exact response shapes for stable core
methods.

`zmr schemas --json` returns the same public schema index in machine-readable
form for setup scripts, generated clients, and editor integrations. The
response is covered by `schemas/schemas-output.schema.json`.

Zero-dependency TypeScript and standard-library Python reference clients live
under `clients/typescript/` and `clients/python/`; both are exercised by the
no-device demo.

## Trace Event Contract

`zmr run ... --trace-dir <dir>` writes a run manifest to `<dir>/trace.json` and newline-delimited events to `<dir>/events.jsonl`. Each event has `seq`, `timestampMs`, `kind`, and `payload`.

`trace.json` is the stable bundle entrypoint for agents and viewers. It includes `schemaVersion`, `runnerVersion`, `protocolVersion`, `scenarioName`, `appId`, `status`, start/end/duration timestamps, failure metadata, `eventsPath`, `artifactsDir`, event/snapshot counts, and `reportPath` when `zmr report` has generated a single-trace HTML report.

`zmr export <trace-dir> --out <bundle.zmrtrace>` writes a deterministic tar archive with relative paths only. V1 bundles include `trace.json`, `events.jsonl`, optional `report.html`, and every regular file under `artifacts/`.

`zmr export <trace-dir> --out <bundle.zmrtrace> --redact` writes a shareable bundle without mutating the local trace directory. Redacted bundles replace PNG screenshots with placeholder frames, omit screen recording artifacts, scrub text artifacts for emails/tokens/sensitive JSON values, and add `redaction` metadata to the bundled `trace.json`. Add `--omit-screenshots` when the bundle should contain no screenshot artifacts at all.

The local static viewer lives at `viewer/index.html` and opens `.zmrtrace` bundles directly in the browser. It uses `trace.json` as the entrypoint, then renders the event timeline, replay controls for snapshot-linked frames, event payloads, side-by-side screenshots and UI trees, selectable node details, snapshot JSON, and artifact links.

Scenario traces start with `scenario.start` and terminate with `scenario.end`.

Successful terminal event:

```json
{"kind":"scenario.end","payload":{"value":"flow name","status":"passed"}}
```

Failed terminal event:

```json
{"kind":"step.error","payload":{"index":3,"error":"WaitTimeout"}}
{"kind":"scenario.end","payload":{"value":"flow name","status":"failed","failedStepIndex":3,"error":"WaitTimeout"}}
```

Clients should read the last `scenario.end` event as the authoritative trace outcome. The CLI still exits non-zero on failed runs.

`zmr run <scenario.json> --json` returns a terminal run summary after the
scenario completes. For traced runs it mirrors the authoritative `trace.json`
terminal fields, including trace paths, event/snapshot counts, failed step, and
stable error name. Failed scenarios still exit non-zero after writing the JSON
summary. The response is covered by `schemas/run-output.schema.json`:

```json
{"ok":false,"status":"failed","scenario":"login smoke","appId":"com.example.mobiletest","traceDir":"traces/login-smoke","eventsPath":"events.jsonl","artifactsDir":"artifacts","durationMs":100,"eventCount":4,"snapshotCount":1,"failedStepIndex":2,"error":"WaitTimeout"}
```

Selector miss and wait timeout payloads include diagnostic fields intended for agents and humans: `visibleTexts`, `hiddenCandidates`, `disabledCandidates`, `offscreenCandidates`, and `nearestTextMatches`. Tap actions only target nodes that are visible, enabled, and inside the viewport; disabled or offscreen exact selector matches are reported as diagnostics instead of being tapped.

For terminal triage without opening the HTML report or static viewer, run:

```bash
zmr explain traces/android-app-auth-probe
```

The text summary includes the terminal status, failed step, stable error, last diagnostic event, snapshot id, active app context, visible text, and nearest text matches.

`zmr explain <trace-dir> --json` returns the same failure triage fields in a
stable machine-readable shape for agents and CI. The response is covered by
`schemas/explain-output.schema.json`:

```json
{"ok":true,"scenario":"login smoke","status":"failed","appId":"com.example.mobiletest","durationMs":100,"eventCount":4,"snapshotCount":1,"failedStepIndex":2,"error":"WaitTimeout","diagnostic":{"kind":"wait.visible","status":"timeout","snapshotId":"snapshot-7","activePackage":"com.example.mobiletest","activeActivity":".MainActivity","visibleTexts":["Sign in","Try again"],"nearestTextMatches":["Dashboards (score 1)"]},"lastEvent":"scenario.end"}
```

## Version Output Contract

`zmr version --json` returns runner and protocol compatibility metadata for
installers, setup scripts, and generated clients. The response is covered by
`schemas/version-output.schema.json`:

```json
{"name":"zmr","version":"0.1.0-dev","protocolVersion":"2026-04-28","minimumCompatibleProtocolVersion":"2026-04-28","stability":"dev-preview","breakingChangePolicy":"version-and-changelog"}
```

## Doctor Output Contract

`zmr doctor --json` returns setup diagnostics for local tooling. With
`--config`, it also validates configured Android/iOS smoke scenario files. The
response is covered by `schemas/doctor-output.schema.json`:

```json
{"ok":false,"checks":[{"name":"android-shim","status":"missing","errorCode":"setup.android_shim.not_found","detail":"./.zmr/android-shim: FileNotFound","hint":"Run npx zmr-install-android-shim in the app repo or update tools.androidShimPath in .zmr/config.json."}]}
```

```json
{"ok":false,"checks":[{"name":"config","status":"warning","errorCode":"config.empty_string","detail":".zmr/config.json: ConfigFieldMustBeNonEmptyString","fieldPath":"$.scripts.android","hint":"Fix the config file or regenerate it with npx zmr-wizard, then run zmr doctor --config again."}]}
```

```json
{"ok":false,"checks":[{"name":"ios-smoke-scenario","status":"missing","errorCode":"scenario.file_not_found","detail":"./missing-ios-smoke.json: FileNotFound","hint":"Run npx zmr-wizard, create the iOS smoke scenario, or update ios.smokeScenario in .zmr/config.json."}]}
```

Healthy checks omit `hint` and `errorCode`. Missing or warning checks include a
remediation hint that agents and setup scripts can surface directly. Warning
and missing checks include `errorCode` when the failure has a stable public
code. Config checks also include `fieldPath` when ZMR can identify the invalid
app-local config field. `zmr doctor --strict --json` keeps the same output
shape, but exits non-zero when any check is not `ok`; use it for CI gates that
should fail before device orchestration starts.

## Init Output Contract

`zmr init --json` returns machine-readable bootstrap output for setup scripts.
The response is covered by `schemas/init-output.schema.json`. In app mode it
lists every generated app-local file plus the next strict doctor command:

```json
{"ok":true,"mode":"app","dir":".","appId":"com.example.mobiletest","created":["./.zmr/config.json","./.zmr/android-smoke.json","./.zmr/ios-smoke.json"],"next":"zmr doctor --strict --json --config ./.zmr/config.json"}
```

Single-scenario mode reports the created scenario and next validation command:

```json
{"ok":true,"mode":"scenario","appId":"com.example.mobiletest","created":["zmr-scenario.json"],"next":"zmr validate zmr-scenario.json"}
```

## Import Output Contract

`zmr import flow-yaml <flow.yaml> --out .zmr/imported.json --json` converts a
supported subset of mobile-flow YAML into native ZMR scenario JSON. The
response is covered by `schemas/import-output.schema.json`:

```json
{"ok":true,"format":"flow-yaml","source":"flows/login.yaml","out":".zmr/login-smoke.json","name":"Imported login smoke","appId":"com.example.mobiletest","stepCount":10,"next":"zmr validate .zmr/login-smoke.json"}
```

The importer is intentionally a migration helper, not a runtime dependency.
After import, agents and CI should treat the generated `.zmr/*.json` file as
the source of truth and run `zmr validate` before `zmr run`.

## Validate Output Contract

`zmr validate <scenario.json> --json` returns machine-readable scenario
preflight diagnostics without touching a device. The response is covered by
`schemas/validate-output.schema.json`:

```json
{"ok":true,"path":"examples/demo-fake.json","name":"ZMR fake Android auth probe demo","stepCount":4}
```

Invalid scenarios exit non-zero after writing the JSON object:

```json
{"ok":false,"path":"bad.json","errorCode":"scenario.invalid","message":"scenario is invalid","fieldPath":"$.steps"}
```

## Devices Output Contract

`zmr devices --json` returns a stable platform, count, and device list for setup
scripts that need to choose a target before starting `zmr run` or `zmr serve`.
The response is covered by `schemas/devices-output.schema.json`:

```json
{"platform":"android","count":1,"devices":[{"serial":"emulator-5554","state":"device"}]}
```

For iOS, use `zmr devices --json --platform ios`; states come from `simctl`,
for example `Booted`.

## Start

```bash
zmr serve --transport stdio --device emulator-5554 --app-id com.example.mobiletest --trace-dir traces/agent-session
zmr serve --transport tcp --port 8765 --device emulator-5554 --app-id com.example.mobiletest --trace-dir traces/agent-session
zmr serve --transport stdio --platform ios --device <sim-udid> --app-id com.example.mobiletest --trace-dir traces/ios-agent-session
```

`runner.capabilities` reports `platforms: ["android","ios"]` and `iosPreview: true`. Android is the full V1 target. iOS supports simulator discovery, install, launch, stop, clear-state-by-uninstall, deep links, screenshots, logs, and snapshots through `simctl`. iOS `app.clearState` is a best-effort `simctl uninstall <device> <bundle-id>`; if the app is already missing, the simulator is treated as clean. Selector-grade `ui.*` methods on iOS require a configured XCTest/XCUIAutomation shim command; without one they return `IosXCTestShimRequired`.

## Core Methods

- `runner.capabilities`
- `device.list`
- `session.create`
- `session.close`
- `app.install` with `{ "path": "/path/app.apk" }` on Android or `{ "path": "/path/App.app" }` on iOS simulator
- `app.launch`
- `app.stop`
- `app.openLink` with `{ "url": "exampleapp://e2e-auth?probe=1" }`
- `app.clearState`
- `observe.snapshot`
- `ui.tap` with `{ "selector": { "text": "Sign in" } }`
- `ui.type` with `{ "text": "hello" }`, optionally with `selector`
- `ui.eraseText` with `{ "maxChars": 80 }`, optionally with `selector`
- `ui.hideKeyboard`
- `ui.swipe` with `{ "x1": 500, "y1": 1600, "x2": 500, "y2": 400, "durationMs": 300 }`
- `ui.pressBack`
- `ui.scrollUntilVisible` with `{ "selector": { "id": "invite-card" }, "direction": "down", "timeoutMs": 20000 }`
- `wait.until` with `{ "visible": { "textContains": "Home" }, "timeoutMs": 10000 }`
- `wait.any` with `{ "selectors": [{ "text": "A" }, { "textContains": "B" }], "timeoutMs": 10000 }`
- `wait.gone` with `{ "selector": { "textContains": "Loading" }, "timeoutMs": 10000 }`
- `assert.visible`
- `assert.notVisible`
- `trace.events`
- `trace.export`

`runner.capabilities` returns both legacy `protocolVersion` and a structured `protocol` object. Clients should treat `protocol.version` as the compatibility key for method and payload shape, and should reject servers older than `protocol.minimumCompatibleVersion` unless they intentionally support that older shape. Before `v1.0.0`, `protocol.stability` is `dev-preview` and breaking changes require both a protocol version bump and changelog entry.

## Request And Response Shape

Every request is newline-delimited JSON:

```json
{"jsonrpc":"2.0","id":1,"method":"app.launch","params":{}}
```

Successful responses use `result`:

```json
{"jsonrpc":"2.0","id":1,"result":true}
```

Errors use JSON-RPC numeric codes plus an optional stable `publicCode` for agent/client handling:

```json
{"jsonrpc":"2.0","id":1,"error":{"code":-32000,"message":"MissingParam","publicCode":"cli.missing_param"}}
```

Parse and malformed-request errors may omit `publicCode` because the request was not valid enough to classify at the method layer.

## Method Examples

### `runner.capabilities`

Request:

```json
{"jsonrpc":"2.0","id":1,"method":"runner.capabilities","params":{}}
```

Response:

```json
{"jsonrpc":"2.0","id":1,"result":{"name":"zmr","version":"0.1.0-dev","protocolVersion":"2026-04-28","protocol":{"version":"2026-04-28","minimumCompatibleVersion":"2026-04-28","stability":"dev-preview","breakingChangePolicy":"version-and-changelog"},"platforms":["android","ios"],"iosPreview":true,"transports":["stdio","tcp"],"methods":["runner.capabilities","device.list","session.create","session.close","app.install","app.launch","app.stop","app.openLink","app.clearState","observe.snapshot","ui.tap","ui.type","ui.eraseText","ui.hideKeyboard","ui.swipe","ui.pressBack","ui.scrollUntilVisible","wait.until","wait.any","wait.gone","assert.visible","assert.notVisible","trace.events","trace.export"]}}
```

### `trace.events`

Returns live trace events from a `zmr serve --trace-dir <dir>` session after a
sequence cursor. This is the event-streaming surface for long-running agents:
poll with the returned `nextSeq` value to receive only new events. Without a
live trace directory it returns an empty stream with `traceDir: null`.

Request:

```json
{"jsonrpc":"2.0","id":24,"method":"trace.events","params":{"afterSeq":0,"limit":100}}
```

Response:

```json
{"jsonrpc":"2.0","id":24,"result":{"traceDir":"traces/agent-session","afterSeq":0,"nextSeq":2,"latestSeq":2,"events":[{"seq":1,"timestampMs":1777794787560,"kind":"rpc.request","payload":{"method":"session.create","id":1}},{"seq":2,"timestampMs":1777794787561,"kind":"rpc.response","payload":{"method":"session.create","id":1}}]}}
```

`limit` defaults to `100` and is capped at `1000`. `latestSeq` is the current
server-side event counter; `nextSeq` is the last returned event and can be
passed back as `afterSeq`.

### `device.list`

Response:

```json
{"jsonrpc":"2.0","id":2,"result":[{"serial":"emulator-5554","state":"device"}]}
```

For `--platform ios`, states come from `simctl`, for example `Booted`.

### `observe.snapshot`

Response shape:

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "id": "snapshot-1",
    "timestampMs": 1777367889379,
    "viewport": { "width": 720, "height": 1280 },
    "displayDensityDpi": 420,
    "activePackage": "com.example.mobiletest",
    "activeActivity": ".MainActivity",
    "screenshotArtifact": null,
    "treeArtifact": null,
    "focusedNodeId": null,
    "logDelta": null,
    "nodes": []
  }
}
```

### `ui.tap`

Request:

```json
{"jsonrpc":"2.0","id":4,"method":"ui.tap","params":{"selector":{"text":"Sign in"}}}
```

Response:

```json
{"jsonrpc":"2.0","id":4,"result":true}
```

### `ui.type`

Request:

```json
{"jsonrpc":"2.0","id":5,"method":"ui.type","params":{"selector":{"id":"email-login-email-input"},"text":"person@example.com"}}
```

### Waits And Assertions

```json
{"jsonrpc":"2.0","id":6,"method":"wait.until","params":{"visible":{"textContains":"Home"},"timeoutMs":10000}}
{"jsonrpc":"2.0","id":7,"method":"assert.notVisible","params":{"selector":{"textContains":"Loading"},"timeoutMs":5000}}
```

### `trace.export`

When `zmr serve` is started with `--trace-dir`, live JSON-RPC sessions use the
same trace manifest, event stream, snapshot artifacts, and `.zmrtrace` bundle
format as scenario runs. Each request records `rpc.request` and `rpc.response`
or `rpc.error`; snapshot, wait, and UI methods also record their domain events.

Request:

```json
{"jsonrpc":"2.0","id":8,"method":"trace.export","params":{"out":"traces/agent-session-redacted.zmrtrace","redact":true,"omitScreenshots":true}}
```

Response:

```json
{"jsonrpc":"2.0","id":8,"result":{"traceDir":"traces/agent-session","out":"traces/agent-session-redacted.zmrtrace","redacted":true,"omitScreenshots":true}}
```

`omitScreenshots` implies redacted export semantics, even when `redact` is
omitted or false.

If the server was not started with `--trace-dir`, `trace.export` returns a
result with `traceDir: null` and a message explaining how to enable live traces.

## Public Error Codes

Current stable public codes:

- `cli.missing_scenario`
- `cli.missing_device`
- `cli.missing_trace_dir`
- `cli.missing_app_id`
- `cli.missing_adb_path`
- `cli.missing_xcrun_path`
- `cli.missing_zig_path`
- `cli.missing_platform`
- `cli.unknown_flag`
- `cli.missing_param`
- `cli.unsupported_platform`
- `cli.unsupported_transport`
- `scenario.file_not_found`
- `scenario.invalid`
- `selector.invalid`
- `runner.wait_timeout`
- `runner.assertion_failed`
- `runner.selector_not_found`
- `device.command_failed`
- `ios.xctest_shim_required`
- `internal.error`

## Selectors

Selectors can combine fields. All provided fields must match the same visible node.

```json
{
  "id": "email-login-submit-button",
  "resourceId": "email-login-submit-button",
  "text": "Sign in",
  "textContains": "Sign",
  "contentDesc": "Account",
  "contentDescContains": "Acc",
  "className": "android.widget.TextView"
}
```

## Example

```json
{"jsonrpc":"2.0","id":1,"method":"runner.capabilities","params":{}}
{"jsonrpc":"2.0","id":2,"method":"app.openLink","params":{"url":"exampleapp://e2e-auth?probe=1"}}
{"jsonrpc":"2.0","id":3,"method":"wait.until","params":{"visible":{"text":"E2E auth probe"},"timeoutMs":30000}}
{"jsonrpc":"2.0","id":4,"method":"observe.snapshot","params":{}}
```

## Scenario-Only Flow Primitives

Scenario JSON supports additional orchestration primitives for agent-grade mobile flows:

- `waitAny`
- `waitNotVisible`
- `whenVisible`
- `repeat`
- `scrollUntilVisible`
- `eraseText`
- `hideKeyboard`
- `"optional": true` on any step

These are intentionally explicit JSON structures instead of YAML conditionals, so agents can generate, validate, and mutate flows without parsing a second language.
