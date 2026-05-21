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
  --zmr "$ROOT/zig-out/bin/zmr" \
  --adb "$ROOT/tests/fake-adb.sh" \
  --trace-dir "$ROOT/traces/demo-rust-client" \
  --trace-out "$ROOT/traces/demo-rust-client-redacted.zmrtrace"
