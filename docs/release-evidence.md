# Release Evidence Checklist

Use this checklist before publishing a release or making reliability/performance
claims. The goal is to map every public product claim to a concrete artifact
that another maintainer can inspect.

After running `scripts/release-candidate.sh`, use
`zmr-release-readiness --evidence <evidence.jsonl> --target dev-preview` to
check whether the evidence supports a dev-preview release. Use
`--target production` for real app/device readiness and `--target market-claim`
before making same-device competitive claims.

The JSON output includes a `requirements` array. Each row reports whether a
requirement is `satisfied`, `missing`, `planned`, `failed`, or `insufficient`,
and includes the matching evidence row or reason when available. It also
includes `passed`, `satisfied`, `recommendedWording`, and `claimLimitations` so
agents can summarize readiness without accidentally upgrading a dev-preview
result into a production or competitive claim. `blocked` lists every
unsatisfied requirement, including missing, failed, planned, and insufficient
evidence rows. `passed` lists raw evidence row names whose command status is
passed; a row can still be insufficient for a release target. `missing` lists
absent or unreadable evidence. `insufficient` lists passed evidence rows that
do not meet threshold, app, device, target, or benchmark proof requirements.
`satisfied` lists validated requirement names after threshold, target, and app-id checks. Agents
should use `satisfied`, `blocked`, `missing`, `insufficient`,
`recommendedWording`, and `claimLimitations` instead of scraping the
human-readable text output. `nextSteps` is the shortest executable remediation
plan; one step can cover multiple blocked requirements when a single command
writes several evidence rows. Each `nextSteps` item includes `covers`, a list
of blocked requirement or evidence issue labels the step is intended to resolve,
plus a legacy `command` string and a structured `commands` array. Agents should
execute `commands` in order when a step needs multiple shell commands.
Malformed evidence JSONL still returns blocked JSON when `--json` is set, with
the invalid file and line listed in `missing`, `blocked`, and `nextSteps`.
Malformed evidence JSONL is reported as `invalid evidence` in
`claimLimitations` and `recommendedWording`; it is not treated as missing
evidence unless required rows are also absent.
Missing evidence next steps are target-aware. For `dev-preview`, a missing
file points to `./scripts/release-candidate.sh --mode local` for source-checkout
release verification. For missing `production` or `market-claim` evidence,
readiness returns two app-install-safe commands via `zmr-pilot-gate`: one grouped
Android+iOS simulator pilot, and one physical iOS pilot that also writes the
`physical iOS readiness` row. For `market-claim`, it then appends
`zmr-benchmark`, `zmr-benchmark-command`, and `zmr-compare-benchmarks`. Those
commands are available from the npm package and write the pilot and competitive
benchmark rows to the requested evidence file. When the evidence file itself is
missing, that file-level next step covers both the missing file and the production or market-claim rows its command sequence writes, so agents do not receive duplicate default pilot commands.
When an evidence file contains failed or planned rows, `blocked` also includes
`failed evidence:` and `planned evidence:` blockers with matching `nextSteps`;
a later passed row does not make those row-level blockers disappear. Those
`nextSteps` reuse the recorded evidence command when the row includes one.
Repeated failed or planned rows are reported once per evidence name.

You can pass `--evidence` more than once. Keep public release-candidate evidence
in this repository and private real-app pilot evidence in the app repository,
then evaluate both together:

```bash
zmr-release-readiness \
  --evidence traces/release-candidate/<run>/evidence.jsonl \
  --evidence /path/to/app/traces/zmr-pilots/evidence.jsonl \
  --target production \
  --json
```

## Core Product Evidence

| Claim | Command | Required Evidence |
| --- | --- | --- |
| Zig core builds and tests | `zig test src/main.zig -target aarch64-macos.15.0` | All tests pass. |
| Coverage stays above the release threshold | `./scripts/coverage.sh` | Coverage is at least 90%. |
| Public demo runs without mobile hardware | `./scripts/demo.sh` | Demo exits zero and writes generic traces under `traces/`. |
| Release archives are reproducible | `./scripts/build-release.sh && ./scripts/verify-release-artifacts.sh` | `dist/RELEASE_MANIFEST.json`, checksums, SBOM, notices, and archives verify. |
| npm package contents are public-safe | `npm pack --dry-run` | Tarball includes only public code, docs, clients, schemas, examples, shims, and prebuilds. |
| Public repo contains no private app references | `bash tests/public-safety-test.sh` | Safety scan exits zero. |
| Public Android demo builds | `scripts/create-android-demo-app.sh --out /tmp/zmr-android-demo` | Signed debug APK and `.zmr/android-smoke.json` are generated and the scenario validates. |
| Public Android demo runs | `zmr-demo-android --out /tmp/zmr-android-demo --device emulator-5554 --avd <avd-name> --runs 5` | Generated app installs on an emulator/device and reports `100%` pass rate with trace artifacts. |
| Public iOS simulator demo runs | `zmr-demo-ios --out /tmp/zmr-ios-demo --device booted --runs 5 --cleanup-build-products` | Generated app runs repeated iOS smoke and shim smoke flows with redacted traces. The cleanup flag removes Xcode `DerivedData` after reports/traces are written. |

## Client Evidence

| Claim | Command | Required Evidence |
| --- | --- | --- |
| TypeScript client can drive ZMR | `node --test tests/typescript-client.test.mjs` | Fake-session client test passes. |
| Python client can drive ZMR | `python3 -W error -m unittest tests/python_client_test.py` | Fake-session client test passes. |
| Go client can drive ZMR | `bash tests/go-client-test.sh` | Go tests and fake-session example pass. |
| Rust client can drive ZMR | `bash tests/rust-client-test.sh` | Rust tests and fake-session example pass. |
| Swift client can drive ZMR | `swift test --package-path clients/swift` | Swift package test passes when Swift is installed. |
| Kotlin client can drive ZMR | `gradle -p clients/kotlin test` | Kotlin/JVM test passes when Gradle is installed. |

## Local Device Evidence

| Claim | Command | Required Evidence |
| --- | --- | --- |
| Android emulator/device path is ready | `zmr doctor --strict --json --config .zmr/config.json` | Android checks are `ok`, or warnings are explicitly documented before release. |
| iOS simulator path is ready | `zmr doctor --strict --json --config .zmr/config.json` | `ios-simulators` and `ios-shim` checks are `ok`. |
| Physical iOS path is ready | `zmr-assert-ios-physical-ready --device <physical-device-id> --xcrun xcrun --evidence-out traces/zmr-pilots/evidence.jsonl` | The requested physical device identifier from `zmr devices` is present with `"ready": true`, and the command appends a `physical iOS readiness` JSONL row. |
| Multi-device matrix works | `zmr-device-matrix --matrix .zmr/device-matrix.json --trace-root traces/zmr-matrix --min-pass-rate 100 --max-failures 0` | `summary.json` reports `passRate: 100.0` and `failed: 0`. |

## Real Pilot Evidence

Run these in a private app checkout with private scenarios, app builds, and raw
traces kept out of the public repository.

| Claim | Command | Required Evidence |
| --- | --- | --- |
| Android and iOS simulator pilots are reliable | `zmr-pilot-gate --android --ios --android-app-root . --android-app-id <android-app-id> --android-device <android-device-id> --ios-app-root . --ios-app-path ./build/Debug-iphonesimulator/Sample.app --ios-app-id <ios-app-id> --ios-device booted --ios-shim ./.zmr/ios-shim --runs 20 --min-pass-rate 100 --max-failures 0 --evidence-out traces/zmr-pilots/evidence.jsonl` | Android and iOS simulator trace roots contain run summaries, selector-grade traces, and redacted bundles; no failures. |
| Physical iOS pilot is reliable | `zmr-pilot-gate --ios --ios-device-type physical --ios-device <physical-device-id> --ios-app-root . --ios-app-path ./build/Release-iphoneos/Sample.ipa --ios-app-id <ios-app-id> --ios-shim ./.zmr/ios-shim --runs 20 --min-pass-rate 100 --max-failures 0 --evidence-out traces/zmr-pilots/evidence.jsonl` | Physical iOS trace root contains selector-grade traces; no failures. |
| ZMR is faster than a local baseline | collect 20 ZMR rows with `zmr-benchmark`, collect 20 baseline rows with `zmr-benchmark-command`, then run `zmr-compare-benchmarks --results traces/bench-comparison/results.jsonl --candidate zmr --baseline baseline --min-candidate-pass-rate 100 --max-candidate-failures 0 --min-mean-speedup 1.25 --min-p95-speedup 1.25 --evidence-out traces/bench-comparison/evidence.jsonl` | Comparison report exits zero and appends a `competitive benchmark comparison` evidence row with candidate/baseline run counts, mean/p95 speedup, and same-context proof against the baseline collected on the same host/device/app build. |

When collecting private real-app pilot evidence, write a machine-readable file
that can be evaluated with public release evidence:

```bash
zmr-pilot-gate \
  --android \
  --android-app-root . \
  --android-app-id <android-app-id> \
  --android-device emulator-5554 \
  --ios \
  --ios-app-root . \
  --ios-app-path ./build/Debug-iphonesimulator/Sample.app \
  --ios-app-id <ios-app-id> \
  --ios-device booted \
  --ios-shim ./.zmr/ios-shim \
  --runs 20 \
  --min-pass-rate 100 \
  --max-failures 0 \
  --trace-root traces/zmr-pilots \
  --evidence-out traces/zmr-pilots/evidence.jsonl
```

For physical iOS, run a separate physical-device pilot with
`--ios-device-type physical`; `zmr-pilot-gate` writes both `physical iOS
readiness` and `iOS physical hardware pilot` rows to the same evidence file.
The `physical iOS readiness` row must include concrete physical device evidence
(`iosDeviceId`, `deviceId`, `device`, or a `--device` flag in the recorded
command). Use the physical device identifier from `zmr devices`, not `booted`
or simulator aliases; a generic passed row is reported as `insufficient`.
Each hardware pilot evidence row includes `runs`, `minPassRate`, `maxFailures`,
a concrete app id (`androidAppId` or `iosAppId`, or an explicit app-id flag in
the recorded command), and app root evidence (`androidAppRoot`, `iosAppRoot`,
`appRoot`, or an explicit app-root flag). iOS simulator and physical pilot rows
must also include app artifact evidence (`iosAppPath`, `appPath`, `--ios-app-path`, or `--app-path`) for the built `.app` or `.ipa` that was tested.
Pilot threshold evidence must be structured JSON fields: `runs`,
`minPassRate`, and `maxFailures`. The recorded `command` remains useful
provenance for app, device, and rerun instructions, but command flags do not count for actual pilot outcomes.
`zmr-release-readiness --target production` requires at least 20 runs,
`minPassRate >= 100`, `maxFailures <= 0`, app-id evidence, app-root evidence,
and iOS app-artifact evidence for the corresponding pilot rows. The Android hardware pilot row requires Android device evidence (`androidDeviceId`, `deviceId`,
`device`, `--android-device`, or `--device`). The iOS simulator hardware pilot row requires iOS simulator device evidence (`iosDeviceId`, `deviceId`, `device`,
`--ios-device`, or `--device`); `booted` is accepted for simulator evidence.
The iOS physical-device pilot row also requires physical device evidence
(`iosDeviceId`, `deviceId`, `device`, `--ios-device`, or a concrete `--device` flag), and
`booted` is not accepted as a physical device.

For market-claim readiness, benchmark comparison evidence must include the
competitive thresholds used to justify the claim: `minCandidatePassRate >= 100`,
`maxCandidateFailures <= 0`, `minMeanSpeedup >= 1.25`, and
`minP95Speedup >= 1.25`. It must also include candidate name evidence
(`candidate`, `candidateName`, or a concrete `--candidate` flag) and baseline name evidence (`baseline`, `baselineName`, or a concrete `--baseline` flag) so
the claim names both compared tools. It must include results path evidence
(`results`, `resultsPath`, or a concrete `--results` flag) so maintainers can
inspect the source benchmark rows. It must include measured result evidence:
`candidatePassRate >= minCandidatePassRate`,
`candidateFailures <= maxCandidateFailures`, `meanSpeedup >= minMeanSpeedup`,
`p95Speedup >= minP95Speedup`, `candidateRuns >= 20`, and
`baselineRuns >= 20`. Measured result evidence must be structured. Sample-size
evidence must also be structured JSON fields emitted by the comparison tool;
command flags do not count for those actual outcomes. It must also include same benchmark context evidence: `sameContext: true` plus structured
`context.platform`, `context.device`, `context.appId`, `context.scenario`, and `context.appBuild`
fields proving the candidate and baseline rows came from the same platform,
device, app id, scenario, and app build. A passed comparison row without those
thresholds, named-tool evidence, results evidence, measured result evidence,
sample-size evidence, or same-context evidence is reported as `insufficient`,
not ready.

## Evidence Rules

- Do not publish raw traces from private apps.
- Publish only sanitized summaries, redacted `.zmrtrace` bundles, or generated
  markdown reports that do not include private identifiers or credentials.
- Do not claim physical iOS reliability until the physical iOS pilot evidence
  exists for a connected, trusted, ready device.
- Do not claim speed leadership from generic fake demos. Use app-local
  benchmark rows collected on the same machine and device state.
- Treat missing evidence as not shipped, even when unit tests and package gates
  pass.
