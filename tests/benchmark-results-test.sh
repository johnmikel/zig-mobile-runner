#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

TRACE_DIR="$TMPDIR/zmr-1"
mkdir -p "$TRACE_DIR"

cat > "$TRACE_DIR/events.jsonl" <<'JSONL'
{"seq":1,"kind":"step.error","payload":{"index":12,"error":"WaitTimeout"}}
{"seq":2,"kind":"scenario.end","payload":{"value":"flow","status":"failed","failedStepIndex":12,"error":"WaitTimeout"}}
JSONL

row="$("$ROOT/scripts/benchmark_result_row.py" \
  --tool zmr \
  --run 1 \
  --command-status 1 \
  --duration-ms 1234 \
  --trace-dir "$TRACE_DIR")"

python3 - "$row" "$TRACE_DIR" <<'PY'
import json
import sys

row = json.loads(sys.argv[1])
trace_dir = sys.argv[2]

assert row["tool"] == "zmr"
assert row["run"] == 1
assert row["status"] == "failed"
assert row["durationMs"] == 1234
assert row["traceDir"] == trace_dir
assert row["traceStatus"] == "failed"
assert row["traceError"] == "WaitTimeout"
assert row["failedStepIndex"] == 12
PY

cat > "$TMPDIR/results.jsonl" <<'JSONL'
{"tool":"zmr","run":1,"status":"ok","durationMs":1000,"traceStatus":"passed","traceDir":"run-1"}
{"tool":"zmr","run":2,"status":"failed","durationMs":1200,"traceStatus":"failed","traceError":"WaitTimeout","traceDir":"run-2"}
{"tool":"zmr","run":3,"status":"ok","durationMs":900,"traceStatus":"passed","traceDir":"run-3"}
JSONL

if "$ROOT/scripts/benchmark_gate.py" --results "$TMPDIR/results.jsonl" --min-pass-rate 100 --max-failures 0 > "$TMPDIR/pass-rate.out" 2>&1; then
  echo "benchmark gate should fail when pass rate is below the configured minimum" >&2
  exit 1
fi
grep -q 'passRate' "$TMPDIR/pass-rate.out"
grep -q 'failures=1' "$TMPDIR/pass-rate.out"

cat > "$TMPDIR/slow-results.jsonl" <<'JSONL'
{"tool":"zmr","run":1,"status":"ok","durationMs":1000,"traceStatus":"passed","traceDir":"run-1"}
{"tool":"zmr","run":2,"status":"ok","durationMs":5000,"traceStatus":"passed","traceDir":"run-2"}
{"tool":"zmr","run":3,"status":"ok","durationMs":900,"traceStatus":"passed","traceDir":"run-3"}
JSONL

if "$ROOT/scripts/benchmark_gate.py" --results "$TMPDIR/slow-results.jsonl" --min-pass-rate 100 --max-failures 0 --max-p95-ms 1000 > "$TMPDIR/p95.out" 2>&1; then
  echo "benchmark gate should fail when p95 exceeds the configured maximum" >&2
  exit 1
fi
grep -q 'p95Ms' "$TMPDIR/p95.out"

cat > "$TMPDIR/passing-results.jsonl" <<'JSONL'
{"tool":"zmr","run":1,"status":"ok","durationMs":1000,"traceStatus":"passed","traceDir":"run-1"}
{"tool":"zmr","run":2,"status":"ok","durationMs":1200,"traceStatus":"passed","traceDir":"run-2"}
JSONL

"$ROOT/scripts/benchmark_gate.py" --results "$TMPDIR/passing-results.jsonl" --min-pass-rate 100 --max-failures 0 --max-p95-ms 2000 > "$TMPDIR/passing.out"
grep -q 'zmr: runs=2 passRate=100.00% failures=0' "$TMPDIR/passing.out"

cat > "$TMPDIR/fake-zmr" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
trace_dir=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --trace-dir)
      trace_dir="${2:-}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
mkdir -p "$trace_dir"
case "$trace_dir" in
  *zmr-2)
    printf '%s\n' '{"seq":1,"kind":"scenario.end","payload":{"status":"failed","error":"WaitTimeout"}}' > "$trace_dir/events.jsonl"
    exit 1
    ;;
  *)
    printf '%s\n' '{"seq":1,"kind":"scenario.end","payload":{"status":"passed"}}' > "$trace_dir/events.jsonl"
    ;;
esac
SH
chmod +x "$TMPDIR/fake-zmr"
touch "$TMPDIR/scenario.json"

if ZMR_BIN="$TMPDIR/fake-zmr" "$ROOT/scripts/benchmark.sh" --zmr "$TMPDIR/scenario.json" --device fake-device --runs 2 --trace-root "$TMPDIR/bench-fail" --min-pass-rate 100 --max-failures 0 > "$TMPDIR/bench-fail.out" 2>&1; then
  echo "benchmark.sh should fail when benchmark_gate.py rejects results" >&2
  exit 1
fi
grep -q 'passRate=50.00%' "$TMPDIR/bench-fail.out"
grep -q 'failures=1' "$TMPDIR/bench-fail.out"

ZMR_BIN="$TMPDIR/fake-zmr" "$ROOT/scripts/benchmark.sh" --zmr "$TMPDIR/scenario.json" --device fake-device --runs 2 --trace-root "$TMPDIR/bench-pass" --min-pass-rate 50 --max-failures 1 > "$TMPDIR/bench-pass.out"
grep -q 'passRate=50.00%' "$TMPDIR/bench-pass.out"

cat > "$TMPDIR/fake-zmr-ios" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
args=" $* "
for required in \
  " --platform ios " \
  " --app-id com.example.mobiletest " \
  " --xcrun ./tests/fake-xcrun.sh " \
  " --ios-shim ./tests/fake-ios-shim.sh "
do
  if [[ "$args" != *"$required"* ]]; then
    echo "missing forwarded argument: $required" >&2
    exit 64
  fi
done
trace_dir=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --trace-dir)
      trace_dir="${2:-}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
mkdir -p "$trace_dir"
printf '%s\n' '{"seq":1,"kind":"scenario.end","payload":{"status":"passed"}}' > "$trace_dir/events.jsonl"
SH
chmod +x "$TMPDIR/fake-zmr-ios"

ZMR_BIN="$TMPDIR/fake-zmr-ios" "$ROOT/scripts/benchmark.sh" \
  --zmr "$TMPDIR/scenario.json" \
  --device fake-ios-1 \
  --runs 1 \
  --trace-root "$TMPDIR/bench-ios" \
  --platform ios \
  --app-id com.example.mobiletest \
  --xcrun ./tests/fake-xcrun.sh \
  --ios-shim ./tests/fake-ios-shim.sh \
  --min-pass-rate 100 \
  --max-failures 0 > "$TMPDIR/bench-ios.out"
grep -q 'passRate=100.00%' "$TMPDIR/bench-ios.out"

mkdir -p "$TMPDIR/path-bin"
cat > "$TMPDIR/path-bin/zmr" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
trace_dir=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --trace-dir)
      trace_dir="${2:-}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
mkdir -p "$trace_dir"
printf '%s\n' '{"seq":1,"kind":"scenario.end","payload":{"status":"passed"}}' > "$trace_dir/events.jsonl"
SH
chmod +x "$TMPDIR/path-bin/zmr"

PATH="$TMPDIR/path-bin:$PATH" "$ROOT/scripts/benchmark.sh" \
  --zmr "$TMPDIR/scenario.json" \
  --device fake-device \
  --runs 1 \
  --trace-root "$TMPDIR/bench-path-bin" \
  --min-pass-rate 100 \
  --max-failures 0 > "$TMPDIR/bench-path-bin.out"
grep -q 'passRate=100.00%' "$TMPDIR/bench-path-bin.out"
