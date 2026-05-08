---
name: zmr-mobile-testing
description: Use when testing mobile apps with Zig Mobile Runner, integrating app-local .zmr setup, driving Android or iOS simulator scenarios, using JSON-RPC agent sessions, exporting traces, or comparing mobile runner benchmarks.
---

# ZMR Mobile Testing

Use ZMR as the typed control plane for mobile app testing. Keep model reasoning
outside the runner; use ZMR for device discovery, observations, actions, waits,
assertions, traces, and diagnostics.

## Start From App-Local State

1. Look for `.zmr/config.json` in the app checkout.
2. If it is missing, scaffold it:

   ```bash
   npx zmr-wizard --app-id com.example.mobiletest --package-json
   ```

3. Run setup diagnostics before touching a device:

   ```bash
   zmr doctor --json --config .zmr/config.json
   zmr validate --json .zmr/android-smoke.json
   zmr validate --json .zmr/ios-smoke.json
   ```

Use `zmr doctor --strict --json` for CI-style gates.

## Agent Session Pattern

Prefer JSON-RPC over stdio for interactive agent work:

```bash
zmr serve --transport stdio --config .zmr/config.json --trace-dir traces/zmr-agent
```

Call methods in this order:

1. `runner.capabilities`
2. `session.create`
3. `observe.snapshot`
4. one typed action, wait, or assertion
5. `observe.snapshot`
6. `trace.events` while the session is active
7. `trace.export` with redaction enabled
8. `session.close`

Do not scrape terminal output when CLI JSON, snapshots, action results, or trace
events contain the same information.

## Scenario Pattern

For repeatable tests, edit `.zmr/*.json` scenarios and run:

```bash
zmr validate --json .zmr/<scenario>.json
zmr run .zmr/<scenario>.json --json --trace-dir traces/zmr-<scenario>
zmr explain --json traces/zmr-<scenario>
```

Prefer stable selectors: resource id or accessibility identifier first,
content description/accessibility label second, exact text third, textContains
only when copy varies, coordinates last.

Use `waitAny` for valid branches and `whenVisible` for optional screens. Keep
credentials, private app terms, and private traces out of public docs and
examples.

## Trace Handling

When a run fails, inspect `zmr explain --json`, `events.jsonl`, the final
snapshot, and the trace viewer report from `zmr report`.

Before sharing:

```bash
zmr export traces/zmr-<scenario> --out traces/zmr-<scenario>-redacted.zmrtrace --redact
```

Add `--omit-screenshots` if visual artifacts may contain sensitive data.

## Benchmarks

Use ZMR repeated runs:

```bash
zmr-benchmark --zmr .zmr/android-smoke.json --device emulator-5554 --runs 20 --trace-root traces/zmr-android-reliability --min-pass-rate 100 --max-failures 0
```

Use `zmr-benchmark-command` for any app-local baseline command and
`zmr-compare-benchmarks` for reports. Only claim performance wins from
equivalent app paths, same device state, repeated runs, and trace-backed
failure diagnostics.
