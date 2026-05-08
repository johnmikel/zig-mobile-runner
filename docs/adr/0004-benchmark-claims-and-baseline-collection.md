# 0004: Benchmark Claims And Baseline Collection

## Status

Accepted.

## Context

ZMR should eventually demonstrate speed, reliability, and diagnostics against
existing app-local automation, but public fixtures cannot assume a private app,
private credentials, or a specific third-party runner.

## Decision

Public ZMR benchmarking remains tool-agnostic:

- `zmr-benchmark` records repeated ZMR scenario runs.
- `zmr-benchmark-command` records repeated app-local baseline commands.
- `zmr-compare-benchmarks` compares normalized candidate and baseline rows.

Public docs describe the measurement method and output shape. They do not make
real-app speed claims unless equivalent candidate and baseline flows were run
under the same local conditions and the report can be shared safely.

## Consequences

- Benchmark infrastructure is reusable without hardcoded private app details.
- App teams can compare against whatever runner they already use by wrapping a
  command.
- Public performance statements require fair inputs: same app build, same
  device/simulator state, same user path, repeated runs, and trace-backed
  failure diagnostics.
