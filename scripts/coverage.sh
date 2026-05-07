#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/zig-cache/coverage"
BIN="$OUT/zmr-tests"
MIN_COVERAGE="${MIN_COVERAGE:-90}"

if ! command -v zig >/dev/null 2>&1; then
  echo "zig is required" >&2
  exit 127
fi

if ! command -v kcov >/dev/null 2>&1; then
  echo "kcov is required for coverage reports" >&2
  exit 127
fi

if [[ -z "${ZIG_TARGET:-}" ]]; then
  if [[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "arm64" ]]; then
    ZIG_TARGET="aarch64-macos.15.0"
  else
    ZIG_TARGET="native"
  fi
fi

target_args=()
if [[ "$ZIG_TARGET" != "native" ]]; then
  target_args=(-target "$ZIG_TARGET")
fi

rm -rf "$OUT"
mkdir -p "$OUT"

zig test "$ROOT/src/main.zig" "${target_args[@]}" --test-no-exec -femit-bin="$BIN"
kcov --include-path="$ROOT/src" "$OUT/kcov" "$BIN"

report_json="$(find "$OUT/kcov" -path '*/zmr-tests.*/coverage.json' -print -quit)"
if [[ -z "$report_json" ]]; then
  echo "coverage.json was not generated" >&2
  exit 1
fi

coverage="$(awk -F'"' '/^  "percent_covered"/ { print $4; exit }' "$report_json")"
covered_lines="$(awk -F'[: ,]+' '/^  "covered_lines"/ { print $3; exit }' "$report_json")"
total_lines="$(awk -F'[: ,]+' '/^  "total_lines"/ { print $3; exit }' "$report_json")"

printf 'Coverage: %s%% (%s/%s lines)\n' "$coverage" "$covered_lines" "$total_lines"
printf 'Report: %s\n' "$report_json"

awk -v actual="$coverage" -v minimum="$MIN_COVERAGE" 'BEGIN { exit (actual + 0 >= minimum + 0) ? 0 : 1 }' || {
  printf 'Coverage gate failed: %s%% < %s%%\n' "$coverage" "$MIN_COVERAGE" >&2
  exit 1
}
