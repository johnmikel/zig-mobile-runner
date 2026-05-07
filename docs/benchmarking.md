# Benchmarking

ZMR benchmark output is intentionally simple: each run appends one JSON object to `results.jsonl`, and `zmr report` turns that directory into a local HTML report.

## Single Tool Benchmark

```bash
scripts/benchmark.sh \
  --zmr examples/android-app-login-smoke.json \
  --device emulator-5554 \
  --runs 10 \
  --min-pass-rate 100 \
  --max-failures 0 \
  --max-p95-ms 30000
```

The command writes a timestamped directory under `traces/bench-*`.
When any gate option is present, `scripts/benchmark_gate.py` reads
`results.jsonl` and exits non-zero if pass rate, failure count, mean duration,
or p95 duration misses the configured threshold.

Generate a report:

```bash
zmr report traces/bench-<timestamp> --out traces/bench-<timestamp>/report.html
```

## Pilot Wrapper

The configurable Android pilot script can run both sample scenarios repeatedly:

```bash
./scripts/run-android-pilot.sh \
  --app-root /path/to/mobile-app \
  --device emulator-5554 \
  --runs 20 \
  --min-pass-rate 100 \
  --max-failures 0 \
  --max-p95-ms 30000
```

For lower variance, restore a clean emulator snapshot at the start of the pilot.
Use `--screen-record` when investigating visual flakes:

```bash
./scripts/run-android-pilot.sh \
  --app-root /path/to/mobile-app \
  --device emulator-5554 \
  --avd Small_Phone \
  --reset-emulator \
  --restore-snapshot zmr-clean \
  --screen-record \
  --runs 20 \
  --min-pass-rate 100 \
  --max-failures 0
```

For `--runs 1`, the script exports normal and redacted `.zmrtrace` bundles. For `--runs > 1`, it writes benchmark directories and HTML reports.

The iOS pilot wrapper supports the same repeated-run gates:

```bash
./scripts/run-ios-pilot.sh \
  --app-root /path/to/mobile-app \
  --app-path /path/to/mobile-app/build/Debug-iphonesimulator/Sample.app \
  --device booted \
  --ios-shim /path/to/mobile-app/.zmr/ios-shim \
  --runs 20 \
  --min-pass-rate 100 \
  --max-failures 0 \
  --max-p95-ms 45000
```

For release validation on a machine that has both platform builds and targets
ready, `zmr-pilot-gate` runs the Android and iOS pilot wrappers with one
external gate command:

```bash
zmr-pilot-gate \
  --android --ios \
  --android-app-root /path/to/mobile-app \
  --ios-app-path /path/to/mobile-app/build/Debug-iphonesimulator/Sample.app \
  --ios-shim /path/to/mobile-app/.zmr/ios-shim \
  --runs 20 \
  --min-pass-rate 100 \
  --max-failures 0
```

## Reading Results

Benchmark reports include:

- pass rate
- failure count
- mean duration
- p95 duration
- per-run status
- terminal trace status
- failed step index and error when available
- links to each run's `events.jsonl`

Before making public performance claims, run the same scenario repeatedly on a clean emulator image and include the raw `results.jsonl` plus the redacted trace bundle for any failure.

## Compare Against A Baseline

Use `zmr-compare-benchmarks` when a private app repo has benchmark rows from
ZMR and another local runner. The public ZMR repo keeps this generic: rows are
grouped by the `tool` field and no external runner is hardcoded.

```bash
zmr-compare-benchmarks \
  --results traces/bench-comparison/results.jsonl \
  --candidate zmr \
  --baseline baseline \
  --format markdown \
  --out traces/bench-comparison/comparison.md
```

The report includes pass rate, failure count, mean duration, p95 duration, mean
speedup, and p95 speedup. Only compare runs collected on the same host, device
state, app build, and scenario.

## Device Matrix

Use `zmr-device-matrix` when CI needs to run one or more scenarios across
multiple local emulators, simulators, or attached devices:

```bash
zmr-device-matrix \
  --matrix .zmr/device-matrix.json \
  --trace-root traces/zmr-matrix \
  --min-pass-rate 100 \
  --max-failures 0
```

Example matrix:

```json
{
  "runs": 2,
  "appId": "com.example.mobiletest",
  "devices": [
    {
      "name": "android-api-35",
      "platform": "android",
      "serial": "emulator-5554",
      "scenario": ".zmr/android-smoke.json",
      "adb": "adb",
      "androidShim": ".zmr/android-shim"
    },
    {
      "name": "ios-18",
      "platform": "ios",
      "serial": "booted",
      "scenario": ".zmr/ios-smoke.json",
      "xcrun": "xcrun",
      "iosShim": ".zmr/ios-shim"
    }
  ]
}
```

The command writes `matrix.jsonl` and `summary.json` under the trace root.
Each device/run pair has a normal trace directory, so failures can be inspected
with `zmr explain`, `zmr report`, or the trace viewer.
