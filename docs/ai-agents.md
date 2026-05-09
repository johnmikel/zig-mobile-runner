# AI Agent Guide

ZMR is built for external agents. The runner provides device state, typed
actions, waits, assertions, and trace export; the agent decides the next step.

## Agent Setup Loop

Start inside the app checkout:

```bash
zmr doctor --json --config .zmr/config.json
zmr validate --json .zmr/android-smoke.json
zmr validate --json .zmr/ios-smoke.json
zmr schemas --json
```

Use `zmr doctor --strict --json` in CI or setup flows that should fail on any
warning. Prefer JSON output for automation because it includes stable error
codes, field paths, and remediation hints.

## Live JSON-RPC Session

Agents should prefer `zmr serve` for interactive work:

```bash
zmr serve --transport stdio --config .zmr/config.json --trace-dir traces/zmr-agent
```

Recommended flow:

1. Call `runner.capabilities` and check protocol/platform support.
2. Call `session.create`.
3. Call `observe.semanticSnapshot` when choosing the next action, or
   `observe.snapshot` when raw adapter details are needed.
4. Choose one typed action or assertion.
5. Let ZMR settle, then observe again.
6. Poll `trace.events` during long runs.
7. Call `trace.export` with `redact: true` before sharing artifacts.
8. Call `session.close`.

Do not parse screenshots or terminal text when the same fact is available from
snapshot nodes, action results, CLI JSON, or trace events.

## MCP Session

Agents that support the Model Context Protocol can use ZMR directly as a local
stdio MCP server:

```bash
zmr mcp --config .zmr/config.json --trace-dir traces/zmr-agent
```

The MCP server exposes mobile-specific tools:

- `snapshot`: raw ZMR observation JSON
- `semantic_snapshot`: normalized roles, names, selectors, bounds, and
  recommended actions
- `tap`, `type`, `press_back`, and `open_link`
- `wait_visible`
- `trace_events` and `trace_export`

Prefer `semantic_snapshot` for action planning. It avoids forcing an agent to
infer intent from platform-specific Android/UI Automator or XCTest class names.

## Scenario File Workflow

For repeatable tests, generate or edit `.zmr/*.json` scenarios:

```bash
zmr validate --json .zmr/login-smoke.json
zmr run .zmr/login-smoke.json --json --trace-dir traces/zmr-login-smoke
zmr explain --json traces/zmr-login-smoke
zmr export traces/zmr-login-smoke --out traces/zmr-login-smoke-redacted.zmrtrace --redact
```

Use stable selectors in this order when available:

- app accessibility identifiers or resource ids
- content descriptions or accessibility labels
- exact visible text for stable product copy
- `textContains` only when the visible text legitimately varies
- coordinate actions only as a last resort

Use `waitAny` for screens with legitimate branches, and `whenVisible` for
optional platform or dev-client screens. Keep credentials and app-private data
in the app repository or environment, not in public scenarios.

## Failure Triage

When a run fails, inspect:

- `zmr run --json` terminal summary
- `zmr explain --json <trace-dir>`
- `trace.json`
- `events.jsonl`
- the last snapshot JSON
- the trace viewer report from `zmr report`

Selector failures include active app context, visible text, disabled/hidden or
offscreen exact candidates, and nearest text matches when available. Treat
those diagnostics as the source of truth before changing a selector.

## Benchmarking

Use ZMR repeated runs first:

```bash
zmr-benchmark --zmr .zmr/android-smoke.json --device emulator-5554 --runs 20 --trace-root traces/zmr-android-reliability --min-pass-rate 100 --max-failures 0
```

For a fair comparison with an app-local baseline command, collect normalized
rows and compare them:

```bash
zmr-benchmark-command --tool baseline --runs 20 --trace-root traces/baseline --results traces/baseline/results.jsonl -- <baseline command>
zmr-compare-benchmarks --candidate traces/zmr-android-reliability/results.jsonl --baseline traces/baseline/results.jsonl --out traces/comparison
```

Only publish claims when the candidate and baseline exercise equivalent app
paths under the same device state.

## Safety Rules

- Run `tests/public-safety-test.sh` before publishing docs, examples, or traces.
- Do not commit app-private traces, screenshots, credentials, tokens, bundle
  identifiers, or private app names.
- Prefer `zmr export --redact`; add `--omit-screenshots` for public bundles
  when visual artifacts may contain sensitive data.
- Keep app-local state under `.zmr/` and generated run output under `traces/`.
