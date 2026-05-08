# V1 Dev Preview Shipping Checklist

This checklist defines the current shippable unit. It is intentionally narrower than a general mobile automation product.

For the maintainer-facing GitHub upload and npm publication sequence, see
[docs/publication.md](publication.md).

## Included

- Local CLI: `zmr devices`, `zmr run`, `zmr serve`.
- Local hardening CLI: `zmr doctor`, `zmr init`, `zmr validate`.
- Local migration CLI: `zmr import flow-yaml <flow.yaml> --out .zmr/<name>.json`.
- Local failure summary CLI: `zmr explain <trace-dir>`.
- JSON-RPC over stdio and localhost TCP.
- Live JSON-RPC trace capture with `zmr serve --trace-dir` and redacted
  `trace.export` bundles.
- Live `trace.events` cursor polling for long-running agent sessions.
- Android ADB/UI Automator adapter.
- iOS simulator adapter through `xcrun simctl` for lifecycle, deep links,
  screenshots, logs, and snapshots, with XCTest shim support for hierarchy and
  selector-grade actions.
- Fake-device test harness for emulator-free protocol and runner tests.
- Fake Android/iOS demo shims and `scripts/demo.sh`.
- Real Android pilot wrapper with redacted trace export: `scripts/run-android-pilot.sh`.
- Real iOS simulator smoke wrapper with redacted trace export: `scripts/run-ios-pilot.sh`.
- Generic baseline command benchmark collection:
  `scripts/benchmark-command.sh` / `zmr-benchmark-command`.
- Generic candidate-vs-baseline benchmark comparison:
  `scripts/compare-benchmarks.py` / `zmr-compare-benchmarks`.
- Local device-matrix runner with `matrix.jsonl` and `summary.json` outputs:
  `scripts/device-matrix.sh` / `zmr-device-matrix`.
- Deterministic trace event stream and snapshot artifacts.
- Static trace viewer with snapshot replay controls, timeline, screenshots,
  UI tree inspection, selected node details, payloads, and artifact links.
- Redacted persisted JSON events/snapshots for common text secrets.
- Release archive script with checksums, SPDX SBOM, third-party notices,
  generated Homebrew formula, and `RELEASE_MANIFEST.json`.
- npm package tarball generation with bundled prebuilt binaries.
- Maintainer macOS signing helper: `scripts/sign-macos-release.sh`.
- Maintainer macOS notarization helper: `scripts/notarize-macos-release.sh`.
- npm package wrapper, app initializer, setup wizard, and npm tarball builder.
- Standalone `zmr init --app` bootstrap for source or release-archive users who
  need app-local `.zmr/config.json` plus Android/iOS smoke scenarios without npm.
- TypeScript reference client under `clients/typescript/`.
- Python reference client under `clients/python/`.
- Go reference client under `clients/go/`.
- Rust reference client under `clients/rust/`.
- npm-exposed Android shim installer for app-local instrumentation source,
  optional module source copy, optional Gradle `testInstrumentationRunner` and
  dependency patching, and command setup.
- npm-exposed iOS shim installer for app-local XCTest source, command setup,
  and optional Xcode project/workspace UI test target and scheme wiring through
  `xcodeproj`.
- iOS workspace project resolution when exactly one workspace project contains
  the configured `--app-target`, or when `--bundle-id` disambiguates matching
  app targets.
- CI workflows for tests, coverage, formatting, script syntax, and release artifacts.
- Tagged release workflow publishes GitHub artifact attestation for release
  archives, npm tarballs, and metadata.
- Public JSON Schemas under `schemas/`.
- Machine-readable import output contract under `schemas/import-output.schema.json`.
- Protocol compatibility fixtures under `docs/protocol-fixtures/`.
- Machine-readable protocol compatibility policy in `runner.capabilities`.
- App-local `.zmr/config.json` schema and CLI default loading.
- Internal iOS/Android shim protocol scaffolds under `shims/`.
- Security, contribution, trace privacy, and protocol versioning docs.
- Feature catalog in `FEATURES.md`.
- Architecture decision records under `docs/adr/`.
- AI agent integration guide in `docs/ai-agents.md`.
- Reusable agent skill under `skills/zmr-mobile-testing/`.
- Changelog and release notes template.
- Android pilot scenarios:
  - `examples/android-app-auth-probe.json`
  - `examples/android-app-login-smoke.json`
- Scenario authoring templates:
  - `examples/android-app-onboarding.json`
  - `examples/android-app-referral-deep-link.json`
  - `examples/android-app-error-state.json`

## Acceptance Gate

Before tagging a dev-preview release:

```bash
./scripts/release-gate.sh
```

Use `./scripts/release-gate.sh --dry-run` to inspect the exact local commands.
The script includes formatting, script syntax checks, focused shell tests, npm
package tests, viewer tests, Zig unit tests, fake-tool validation, the
no-emulator demo, coverage, release archive generation, checksum verification,
packaged binary smoke, and `npm pack --dry-run`.
The fake-tool validation uses `zmr doctor --strict` so warning or missing setup
checks fail the local release gate instead of requiring callers to parse JSON.

For Android pilot validation, run against a booted emulator with the test app installed and Metro pointed at the hosted TEST API:

```bash
./scripts/run-android-pilot.sh --app-root /path/to/mobile-app --device emulator-5554 --runs 20 --min-pass-rate 100 --max-failures 0 --max-p95-ms 30000
```

For iOS pilot validation, build a simulator `.app`, boot a simulator, then run:

```bash
./scripts/run-ios-pilot.sh --app-root /path/to/mobile-app --app-path /path/to/mobile-app/build/Debug-iphonesimulator/Sample.app --device booted --ios-shim /path/to/mobile-app/.zmr/ios-shim --runs 20 --min-pass-rate 100 --max-failures 0 --max-p95-ms 45000
```

When both app builds are ready on the same machine, use the external pilot gate
wrapper:

```bash
zmr-pilot-gate --android --ios --android-app-root /path/to/mobile-app --ios-app-path /path/to/mobile-app/build/Debug-iphonesimulator/Sample.app --ios-shim /path/to/mobile-app/.zmr/ios-shim --runs 20 --min-pass-rate 100 --max-failures 0
```

Run the pilot gates before publishing reliability or performance claims.

## Not Yet Included

- Automatic iOS workspace resolution when multiple workspace projects contain
  the same requested app target and bundle id. In that case, callers must pass
  `--project`.
- Physical iOS device automation. The supported iOS target for this release is
  local simulators.
- Pixel-level screenshot or video masking. Redacted bundles at present replace
  PNG screenshots with placeholder frames or omit screenshots entirely, and
  omit screen recordings instead of attempting visual masking.
- Broad cloud device farm certification. Local matrix validation is included;
  hosted farm adapters and OS/device matrix certification are not.

## Release Process

1. Run `./scripts/release-gate.sh`.
2. Run the Android and iOS pilot scenarios if emulator/simulator app builds are available.
3. If publishing signed macOS archives, run `./scripts/sign-macos-release.sh --identity "<Developer ID Application identity>"` after `./scripts/build-release.sh`.
4. If publishing notarized macOS archives, run `./scripts/notarize-macos-release.sh --keychain-profile "<notarytool profile>"`, then rerun `./scripts/verify-release-artifacts.sh`.
5. Create the tag `v0.1.0-dev` for the current package version. Bump
   `src/version.zig` and `package.json` before using a different tag.
6. Push the tag; `.github/workflows/release.yml` builds archives, smokes the host-compatible packaged binary, builds `dist/zig-mobile-runner-*.tgz`, publishes GitHub artifact attestation, and uploads checksums, SBOM, third-party notices, `RELEASE_MANIFEST.json`, the npm tarball, and the generated Homebrew formula.
7. If `NPM_TOKEN` is configured, the release workflow publishes the npm tarball with `npm publish dist/zig-mobile-runner-*.tgz --provenance --access public`. Without that secret, the workflow skips npm publish but still uploads the tarball for manual inspection.

`./scripts/verify-release-artifacts.sh` can also be run directly after
`./scripts/build-release.sh`. It verifies every `SHA256SUMS` entry, requires the
release archives plus SBOM/notices/Homebrew formula/manifest to be covered,
also requires any generated npm tarball to be covered, cross-checks manifest
sizes and digests, and fails on tampered or missing files before upload.

`./scripts/sign-macos-release.sh --dry-run --identity "<identity>"` lists the
macOS archives that would be signed without invoking `codesign`.

`./scripts/notarize-macos-release.sh --dry-run --keychain-profile "<profile>"`
lists the macOS archives that would be packaged and submitted to notarytool
without invoking `ditto` or `xcrun`.
