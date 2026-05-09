#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

deny_terms=(
  "bri""ck"
  "(^|[^[:alpha:]])ren""tly([^[:alpha:]]|$)"
  "uk[.]co[.]ren""tly"
  "ren""tlytest"
)

exclude_dirs=(
  -path ./.git -o
  -path ./.zig-cache -o
  -path ./zig-cache -o
  -path ./zig-out -o
  -path ./dist -o
  -path ./traces -o
  -path ./prebuilds -o
  -path ./node_modules -o
  -path './scripts/__pycache__'
)

while IFS= read -r path; do
  lower="$(printf '%s' "$path" | tr '[:upper:]' '[:lower:]')"
  for term in "${deny_terms[@]}"; do
    if [[ "$lower" =~ $term ]]; then
      echo "denied private term in path: $path" >&2
      exit 1
    fi
  done
done < <(find . \( "${exclude_dirs[@]}" \) -prune -o -type f -print)

for term in "${deny_terms[@]}"; do
  if rg -n -i "$term" . \
    --glob '!/.git/**' \
    --glob '!.zig-cache/**' \
    --glob '!zig-cache/**' \
    --glob '!zig-out/**' \
    --glob '!dist/**' \
    --glob '!traces/**' \
    --glob '!prebuilds/**' \
    --glob '!node_modules/**' \
    --glob '!scripts/__pycache__/**'; then
    echo "denied private term in file contents" >&2
    exit 1
  fi
done
