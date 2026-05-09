# ZMR Schemas

This directory contains draft 2020-12 JSON Schemas for public ZMR file and protocol payloads.

- `scenario.schema.json`: scenario files consumed by `zmr run` and `zmr validate`
- `snapshot.schema.json`: `ObservationSnapshot` JSON emitted by live RPC and persisted trace snapshots, including viewport and optional display density metrics
- `action-result.schema.json`: typed action result shape reserved for richer protocol responses
- `trace-event.schema.json`: one JSONL event row from `events.jsonl`
- `trace-manifest.schema.json`: `trace.json` summary for one traced run
- `json-rpc.schema.json`: JSON-RPC requests and responses used by `zmr serve`
- `zmr-config.schema.json`: app-local `.zmr/config.json` defaults used by the CLI and npm wizard, including Android emulator lifecycle defaults
- `doctor-output.schema.json`: machine-readable `zmr doctor --json` setup diagnostics, including remediation hints for actionable checks
- `init-output.schema.json`: machine-readable `zmr init --json` bootstrap output for scenario and app-local `.zmr/` initialization
- `import-output.schema.json`: machine-readable `zmr import --json` output for one-time scenario migration helpers
- `devices-output.schema.json`: machine-readable `zmr devices --json` output for Android, iOS simulator, and physical iOS discovery
- `validate-output.schema.json`: machine-readable `zmr validate --json` scenario preflight output
- `version-output.schema.json`: machine-readable `zmr version --json` output for runner and protocol compatibility discovery
- `capabilities-output.schema.json`: machine-readable `runner.capabilities` JSON-RPC result for protocol, platform support, transport, and method discovery
- `explain-output.schema.json`: machine-readable `zmr explain --json` failure triage output for agents and CI
- `run-output.schema.json`: machine-readable `zmr run --json` terminal run summary output
- `release-manifest.schema.json`: machine-readable `RELEASE_MANIFEST.json` emitted with release archives
- `schemas-output.schema.json`: machine-readable `zmr schemas --json` index of public schema names, paths, ids, and descriptions

The Zig test suite verifies these files parse as JSON. Full schema validation is intentionally left to client tooling for now.
