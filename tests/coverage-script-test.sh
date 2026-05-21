#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

cat > "$TMPDIR/zig" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
out=""
for arg in "$@"; do
  case "$arg" in
    -femit-bin=*)
      out="${arg#-femit-bin=}"
      ;;
  esac
done
if [[ -z "$out" ]]; then
  echo "fake zig expected -femit-bin" >&2
  exit 2
fi
cat > "$out" <<'BIN'
#!/usr/bin/env bash
exit 0
BIN
chmod +x "$out"
SH
chmod +x "$TMPDIR/zig"

cat > "$TMPDIR/kcov" <<'SH'
#!/usr/bin/env bash
exec sleep 60
SH
chmod +x "$TMPDIR/kcov"

set +e
output="$(PATH="$TMPDIR:$PATH" ZIG_TARGET=native ZMR_KCOV_TIMEOUT_SECONDS=1 "$ROOT/scripts/coverage.sh" 2>&1)"
status=$?
set -e

if [[ "$status" -eq 0 ]]; then
  echo "expected coverage script to fail when kcov exceeds timeout" >&2
  exit 1
fi

grep -q 'kcov timed out after 1 second(s)' <<< "$output"
grep -q 'ZMR_KCOV_TIMEOUT_SECONDS' <<< "$output"
