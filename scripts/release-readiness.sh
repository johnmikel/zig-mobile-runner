#!/bin/sh
if [ -z "${ZMR_BASH_BOOTSTRAP:-}" ]; then
  ZMR_BASH_BOOTSTRAP=1
  export ZMR_BASH_BOOTSTRAP
  SCRIPT_DIR="$(cd -P "$(dirname "$0")" && pwd -P)"
  ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
  if [ -z "${TMPDIR:-}" ] || [ ! -w "${TMPDIR:-/nonexistent}" ]; then
    TMPDIR="$ROOT/traces/tmp"
  fi
  mkdir -p "$TMPDIR"
  export TMPDIR
  exec /usr/bin/env bash "$0" "$@"
fi

set -euo pipefail

CALLER_CWD="$(pwd -P)"
# Some sandboxed environments do not allow writing to the default temp directory
# (/var/folders, /tmp). Use a caller-local TMPDIR so heredocs/mktemp work.
if [[ -z "${TMPDIR:-}" || ! -w "${TMPDIR:-/nonexistent}" ]]; then
  TMPDIR="$CALLER_CWD/traces/tmp"
  mkdir -p "$TMPDIR"
  export TMPDIR
fi

EVIDENCE_FILES=()
TARGET="dev-preview"
JSON=0

usage() {
  printf '%s\n' 'Usage:'
  printf '%s\n' '  scripts/release-readiness.sh --evidence <evidence.jsonl> [--evidence <more.jsonl> ...] [--target dev-preview|production|market-claim] [--json]'
  printf '%s\n' ''
  printf '%s\n' 'Reads one or more release/pilot evidence JSONL files and reports whether the'
  printf '%s\n' 'requested release claim is supported by concrete passed evidence.'
  printf '%s\n' ''
  printf '%s\n' 'Targets:'
  printf '%s\n' '  dev-preview   Requires local release gate plus public Android and iOS demos.'
  printf '%s\n' '  production    Requires dev-preview evidence plus repeated real app/device pilots.'
  printf '%s\n' '  market-claim  Requires production evidence plus same-device/app/build benchmark comparison.'
}

die() {
  echo "error: $*" >&2
  exit 2
}

require_value() {
  local flag="$1"
  local value="${2-}"
  if [[ -z "$value" || "$value" == --* ]]; then
    die "$flag requires a value"
  fi
  printf '%s\n' "$value"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --evidence)
      EVIDENCE_FILES+=("$(require_value "$1" "${2-}")")
      shift 2
      ;;
    --target)
      TARGET="$(require_value "$1" "${2-}")"
      shift 2
      ;;
    --json)
      JSON=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[[ "${#EVIDENCE_FILES[@]}" -gt 0 ]] || die "--evidence is required"
for evidence_file in "${EVIDENCE_FILES[@]}"; do
  [[ -n "$evidence_file" ]] || die "--evidence requires a path"
  if [[ ! -f "$evidence_file" && "$JSON" -eq 0 ]]; then
    die "evidence file not found: $evidence_file"
  fi
done
[[ "$TARGET" == "dev-preview" || "$TARGET" == "production" || "$TARGET" == "market-claim" ]] || die "--target must be dev-preview, production, or market-claim"

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
python3 "$SCRIPT_DIR/release-readiness.py" "$TARGET" "$JSON" "${EVIDENCE_FILES[@]}"
