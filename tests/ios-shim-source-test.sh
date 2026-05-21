#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHIM="$ROOT/shims/ios/ZMRShim.swift"

grep -q 'let value: String' "$SHIM"
grep -q 'value: elementValue(element)' "$SHIM"
grep -q 'element.value' "$SHIM"
grep -q '"value": "Continue"' "$ROOT/shims/ios/protocol.md"
