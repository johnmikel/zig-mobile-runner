# Changelog

All notable changes to Zig Mobile Runner are tracked here.

## Unreleased

### Added

- `zmr doctor` for local environment diagnostics across Zig, ADB, Android devices, `xcrun`, and iOS simulators.
- `zmr init` for scaffolding a starter scenario.
- `zmr validate <scenario.json>` for preflight scenario validation without touching a device.
- Public JSON Schemas under `schemas/` for scenarios, snapshots, action results, trace events, and JSON-RPC messages.
- `schemas/validate-output.schema.json` for the machine-readable `zmr validate --json` preflight result.
- Stable public error-code mapping for CLI/protocol-facing failures.
- Top-level CLI failures now print stable `error[code]` messages instead of
  Zig stack traces.
- JSON-RPC execution errors now include `publicCode` when a stable code is available.
- Product roadmap in `docs/roadmap.md`.
- Demo documentation in `docs/demo.md`.
- Machine-readable protocol compatibility metadata in `runner.capabilities`.
- Go and Rust reference JSON-RPC clients with fake-session examples and CI
  coverage.
- `zmr-benchmark-command` for timing app-local baseline commands and writing
  normalized rows that can be compared with ZMR benchmark results.
- `trace.events` JSON-RPC cursor polling for live trace events during long-running agent sessions.
- Field, line, and column diagnostics in `zmr validate --json` for invalid scenarios.
- Scenario authoring guide plus onboarding, referral deep-link, and error-state templates.
- Adapter-level settle hook after mutating scenario actions, with native shim idle support and shell fallback.
- Trace viewer side-by-side screenshot and UI tree inspection with selectable node details.
- App-specific trace redaction denylist/allowlist controls for persisted node text, resource ids, and trace events.
- Release builds now generate SPDX SBOM and third-party license notice artifacts.
- Release builds now generate a Homebrew formula with per-platform checksums.
- Release builds now generate `RELEASE_MANIFEST.json`, a machine-readable
  artifact inventory with sizes and SHA-256 digests.
- Release integrity verification now validates generated archives, metadata
  files, `RELEASE_MANIFEST.json`, and `SHA256SUMS` before packaged binary
  smoke tests.
- Tagged release workflow now publishes GitHub artifact attestation for release
  archives and metadata.
- Tagged release workflow now builds the npm tarball, attests it, uploads it
  with the release assets, and publishes with npm provenance when `NPM_TOKEN`
  is configured.
- Release manifests and checksum verification now include generated npm
  tarballs when present.
- Added `scripts/sign-macos-release.sh` for credentialed maintainers to sign
  macOS release archives and refresh checksums before upload.
- Added `scripts/notarize-macos-release.sh` for credentialed maintainers to
  submit signed macOS archives to Apple notarytool, persist receipts, and
  refresh release metadata before upload.
- iOS simulator `clearState` is now idempotent when the app is already uninstalled and documented as best-effort uninstall by bundle id.
- Android pilot wrapper can reset the emulator and boot from a named snapshot before running smoke flows.
- Android pilot wrapper can capture an optional MP4 screen recording for visual flake triage.
- Android and iOS pilot wrappers now run early setup preflights and print
  structured `zmr doctor --json` diagnostics for missing devices/simulators.
- Android pilot wrapper `--adb` overrides now propagate into the underlying
  `zmr run` and repeated-run benchmark calls.
- Added `scripts/pilot-gate.sh` and the `zmr-pilot-gate` npm bin for the
  external Android+iOS pre-release pilot gate.
- `zmr-pilot-gate` now resolves app-local relative paths from the caller's
  checkout, including when invoked through npm's `node_modules/.bin` symlink.
- The iOS shim installer now resolves multi-project workspaces by matching
  `--bundle-id` when multiple projects contain the same `--app-target`.
- `zmr init --app`, `zmr-init`, and `zmr-wizard --package-json` now scaffold
  a `zmr:pilot` / `scripts.pilotGate` command for external release pilots.
- Android snapshots now include display density DPI when available.
- Traced Android `zmr run` sessions can capture an opt-in `screenrecord.mp4`, and redacted exports omit screen recordings.
- Redacted `.zmrtrace` exports now keep replayable screenshot artifact paths by replacing PNG screenshots with safe placeholder images.
- `zmr export --redact --omit-screenshots` and JSON-RPC
  `trace.export` `omitScreenshots` can omit screenshot artifacts entirely from
  redacted bundles.
- `zmr run` can now boot an Android AVD, restore a snapshot, reset the emulator, and wait for boot readiness before running a scenario.
- `zmr run` can create a missing Android AVD from an installed system image before booting it.
- iOS pilot runs now execute a selector-driven `ios-shim-smoke` flow and export its report/bundles when `--ios-shim` is provided.
- Added `scripts/release-gate.sh` as the one-command local release gate for formatting, tests, demo, coverage, packaging, and release smoke.
- Android shim installer can now copy the instrumentation source directly into an app module and idempotently patch AndroidX test dependencies in Gradle.
- Android shim installer now idempotently patches Gradle `testInstrumentationRunner` when `--gradle-file` is provided and no runner is already configured.
- Android shim installer now reuses an existing Gradle `testInstrumentationRunner` for the generated shim command when `--runner` is omitted.
- Troubleshooting guide for doctor output, scenario validation, shims, trace inspection, and release-gate failures.
- CI and tagged-release workflows now run the same `scripts/release-gate.sh` local acceptance gate.
- `zmr doctor` now includes remediation hints for missing or warning checks, including machine-readable `hint` fields in JSON output.
- Added `schemas/doctor-output.schema.json` for machine-readable setup diagnostics.
- The no-device demo now shows `zmr doctor --json` remediation hints for missing shim setup.
- `zmr doctor --config` now validates configured Android and iOS smoke scenario files and reports remediation hints for missing or malformed files.
- `zmr doctor --json --config` now reports malformed config files as structured `config` checks instead of raw CLI errors.
- Config parsing now rejects non-boolean values for boolean fields instead of silently falling back to defaults.
- Config parsing now rejects unknown fields so app-local config typos do not silently fall back to defaults.
- Config parsing now rejects empty strings for schema-required path, id, redaction list, and script command values.
- `zmr doctor --json --config` now includes stable `errorCode` and `fieldPath` values for actionable app-local config errors.
- `zmr doctor` now warns, with stable setup error codes, when ADB sees zero devices or `xcrun` sees zero booted iOS simulators.
- `zmr doctor --json` now includes stable setup `errorCode` values for missing tools, failed tool commands, and missing shim commands.
- `zmr doctor --strict` now exits non-zero when any diagnostic check is warning or missing, so CI and setup scripts can fail before device orchestration.
- `zmr init --app` now scaffolds an app-local `.zmr/config.json`, Android smoke scenario, iOS smoke scenario, and `traces/` gitignore entry without requiring npm.
- `zmr init --json` now emits machine-readable created files and next-step commands for app and scenario bootstraps.
- Added `schemas/init-output.schema.json` for the machine-readable `zmr init --json` contract.
- `zmr import flow-yaml` now converts a supported subset of mobile-flow YAML commands into native `.zmr/*.json` scenarios.
- Added `schemas/import-output.schema.json` for the machine-readable `zmr import --json` contract.
- The no-device demo now shows config-driven `zmr doctor --json` smoke scenario diagnostics for missing files and malformed JSON.
- `zmr devices --json` now emits machine-readable Android device and iOS simulator discovery output for setup scripts.
- Added `schemas/devices-output.schema.json` for the machine-readable `zmr devices --json` contract.
- `zmr version --json` now emits machine-readable runner and protocol compatibility metadata for installers and generated clients.
- Added `schemas/version-output.schema.json` for the machine-readable `zmr version --json` contract.
- `runner.capabilities` now reports Android and iOS simulator support as
  structured `platformSupport` metadata, with `iosPreview: false` and physical
  iOS devices explicitly unsupported in the current support matrix.
- Added `schemas/capabilities-output.schema.json` for the machine-readable
  `runner.capabilities` JSON-RPC result.
- `zmr explain --json` now emits machine-readable failure triage for agents and CI.
- Added `schemas/explain-output.schema.json` for the machine-readable `zmr explain --json` contract.
- `zmr schemas --json` now emits a machine-readable index of packaged public schema contracts.
- Added `schemas/schemas-output.schema.json` for the machine-readable `zmr schemas --json` contract.
- `zmr run --json` now emits a machine-readable terminal run summary while preserving failed scenario exit codes.
- Added `schemas/run-output.schema.json` for the machine-readable `zmr run --json` contract.
- Added `zmr-device-matrix` / `scripts/device-matrix.sh` for local Android/iOS
  multi-device smoke gates with `matrix.jsonl`, `summary.json`, and pass-rate
  thresholds.
- Added `zmr-compare-benchmarks` / `scripts/compare-benchmarks.py` for generic
  candidate-vs-baseline benchmark comparison reports without naming private app
  projects or third-party tools in public fixtures.
- Added `zmr-demo-ios` and `zmr-create-ios-demo-app` flows for a generic
  simulator app with the XCTest shim installed, selector-grade smoke scenario,
  and redacted trace output.
- `zmr validate --json` now reports missing step selectors as `selector.invalid` with `fieldPath: "$.steps[].selector"` instead of falling back to `internal.error`.
- `zmr validate --json` now reports unknown scenario action typos as `scenario.invalid` with `fieldPath: "$.steps[].action"` and source location diagnostics.
- `zmr validate --json` now reports invalid `scrollUntilVisible.direction` values as `scenario.invalid` with `fieldPath: "$.steps[].direction"`.
- `zmr validate --json` now reports missing `openLink.url` values as `scenario.invalid` with `fieldPath: "$.steps[].url"`.
- `zmr validate --json` now reports missing `typeText.text` values as `scenario.invalid` with `fieldPath: "$.steps[].text"`.
- `zmr validate --json` now reports missing `swipe.x1`, `swipe.y1`, `swipe.x2`, and `swipe.y2` values as `scenario.invalid` with field-specific `fieldPath` values.

### Changed

- README now links to install, demo, schema, and roadmap materials.
- Protocol documentation now includes concrete request/response examples and error shapes.
- Protocol versioning now defines the pre-`v1.0.0` compatibility contract and breaking-change policy.
- Android `openLink` now avoids blocking `am start -W`, retries when Android leaves the launcher foregrounded, and lets selector waits absorb transient observation command timeouts.
- iOS simulators are supported for lifecycle, snapshots, logs, deep links,
  clear-state-by-uninstall, and selector-driven XCTest shim interaction.
- Physical iOS devices are not in the current support matrix.

### Known Limitations

- Physical iOS device automation is not supported yet.
- Broad cloud-device-farm certification is not included in this dev-preview
  release.
- Real app benchmark claims should be made from private app-local
  `zmr-compare-benchmarks` reports, not from generic public fixtures.

## 0.1.0-dev

Initial local dev preview:

- Zig CLI and JSON-RPC runner.
- Android ADB/UI Automator adapter.
- iOS simulator lifecycle/snapshot preview.
- Scenario runner with waits, assertions, selectors, retries, and trace writing.
- Fake-device test harness and no-emulator demo.
- Release archive script and CI workflows.
