#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

test -f "$ROOT/clients/rust/Cargo.toml"
test -f "$ROOT/clients/rust/src/lib.rs"
test -f "$ROOT/clients/rust/examples/fake_session.rs"

(
  cd "$ROOT/clients/rust"
  cargo test --quiet
)

cargo run --quiet \
  --manifest-path "$ROOT/clients/rust/Cargo.toml" \
  --example fake_session \
  -- \
  --server "$ROOT/tests/fake-json-rpc-server.mjs" \
  --node "$(command -v node)" \
  --trace-out "$ROOT/traces/demo-rust-client-redacted.zmrtrace"
