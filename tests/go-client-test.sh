#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export GOCACHE="$ROOT/.zig-cache/go-build"

test -f "$ROOT/clients/go/go.mod"
test -f "$ROOT/clients/go/zmr/client.go"
test -f "$ROOT/clients/go/examples/fake-session/main.go"

(
  cd "$ROOT/clients/go"
  go test ./...
)

(
  cd "$ROOT/clients/go"
  go run ./examples/fake-session \
    --server "$ROOT/tests/fake-json-rpc-server.mjs" \
    --node "$(command -v node)" \
    --trace-out "$ROOT/traces/demo-go-client-redacted.zmrtrace"
)
