# Client Guide

ZMR clients are reference implementations for the JSON-RPC protocol used by
`zmr serve`. They are intentionally small and dependency-light.

## What Clients Mean

The runner is still the Zig binary. A client starts or connects to:

```bash
zmr serve --transport stdio --config .zmr/config.json --trace-dir traces/zmr-agent
```

Then it sends JSON-RPC methods such as:

- `runner.capabilities`
- `session.create`
- `observe.snapshot`
- `ui.tap`
- `wait.until`
- `assert.visible`
- `trace.events`
- `trace.export`

Use clients when an AI agent, service, or test harness wants to drive ZMR
programmatically instead of shelling out for each scenario.

## Language Layouts

| Language | Files | Why it looks this way |
| --- | --- | --- |
| TypeScript | `clients/typescript/index.mjs`, `index.d.ts` | ESM runtime plus type declarations, no build step required |
| Python | `clients/python/zmr_client.py` | Standard-library importable module that can be vendored |
| Go | `clients/go/zmr/client.go` | Normal Go package inside a module |
| Rust | `clients/rust/src/lib.rs` | Cargo library crate convention |

Rust has `src/lib.rs` because Cargo expects a library crate there. The other
clients do have equivalent entry points; they are just idiomatic for their
languages rather than named `lib.rs`.

## Quick Starts

TypeScript:

```bash
node clients/typescript/examples/fake-session.mjs
```

Python:

```bash
python3 clients/python/examples/fake_session.py
```

Go:

```bash
go run ./clients/go/examples/fake-session --server tests/fake-json-rpc-server.mjs
```

Rust:

```bash
cargo run --manifest-path clients/rust/Cargo.toml --example fake_session -- --server tests/fake-json-rpc-server.mjs
```

For real app usage, replace the fake server with `zmr serve --transport stdio`
and pass `.zmr/config.json`.
