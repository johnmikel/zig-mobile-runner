# ZMR Language Clients

ZMR clients are small wrappers around the same newline-delimited JSON-RPC
protocol exposed by:

```bash
zmr serve --transport stdio --config .zmr/config.json --trace-dir traces/zmr-agent
```

They are intended for AI agents, CI harnesses, and app teams that want typed
or idiomatic calls without reimplementing JSON-RPC framing.

## TypeScript

Runtime: `clients/typescript/index.mjs`
Types: `clients/typescript/index.d.ts`

```bash
node clients/typescript/examples/fake-session.mjs
```

```js
import { createZmrClient } from "./clients/typescript/index.mjs";

const zmr = createZmrClient({
  command: "zmr",
  args: ["serve", "--transport", "stdio", "--config", ".zmr/config.json"],
});
```

## Python

Runtime: `clients/python/zmr_client.py`

```bash
python3 clients/python/examples/fake_session.py
```

```python
from zmr_client import ZmrClient

with ZmrClient("zmr", ["serve", "--transport", "stdio", "--config", ".zmr/config.json"]) as zmr:
    snapshot = zmr.snapshot()
```

## Go

Runtime: `clients/go/zmr/client.go`

```bash
go run ./clients/go/examples/fake-session --server tests/fake-json-rpc-server.mjs
```

```go
client, err := zmr.Start(ctx, "zmr", "serve", "--transport", "stdio", "--config", ".zmr/config.json")
```

## Rust

Runtime: `clients/rust/src/lib.rs`

```bash
cargo run --manifest-path clients/rust/Cargo.toml --example fake_session -- --server tests/fake-json-rpc-server.mjs
```

```rust
let mut client = zmr_client::Client::start("zmr", ["serve", "--transport", "stdio", "--config", ".zmr/config.json"])?;
let snapshot = client.snapshot()?;
```

Rust has `src/lib.rs` because Cargo packages libraries from that path by
convention. The other clients use the equivalent idiomatic layout for their
ecosystem: ESM entry file for TypeScript, a single importable module for
Python, and a package directory for Go.
