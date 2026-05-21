#!/usr/bin/env python3
import argparse
import json
import math
import shlex
import statistics
import sys
import time
from collections import defaultdict
from pathlib import Path

CONTEXT_FIELDS = ("platform", "device", "appId", "scenario", "appBuild")


def parse_args():
    parser = argparse.ArgumentParser(
        description="Compare benchmark JSONL rows for two runner labels.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "--evidence-out requires --min-candidate-pass-rate, "
            "--max-candidate-failures, --min-mean-speedup, and "
            "--min-p95-speedup so market-claim evidence includes explicit gates."
        ),
    )
    parser.add_argument("--results", required=True, help="Path to a benchmark results.jsonl file.")
    parser.add_argument("--candidate", default="zmr", help="Candidate tool label. Default: zmr.")
    parser.add_argument("--baseline", required=True, help="Baseline tool label to compare against.")
    parser.add_argument("--format", choices=("markdown", "json"), default="markdown", help="Output format.")
    parser.add_argument("--out", help="Optional output file. Defaults to stdout.")
    parser.add_argument("--min-candidate-pass-rate", type=float, help="Minimum candidate pass rate percentage.")
    parser.add_argument("--max-candidate-failures", type=int, help="Maximum allowed candidate failures.")
    parser.add_argument("--min-mean-speedup", type=float, help="Minimum required mean speedup versus baseline.")
    parser.add_argument("--min-p95-speedup", type=float, help="Minimum required p95 speedup versus baseline.")
    parser.add_argument("--evidence-out", help="Optional JSONL file to append a market-claim readiness evidence row.")
    args = parser.parse_args()
    for name in (
        "min_candidate_pass_rate",
        "max_candidate_failures",
        "min_mean_speedup",
        "min_p95_speedup",
    ):
        value = getattr(args, name)
        if value is not None and value < 0:
            parser.error(f"--{name.replace('_', '-')} must be non-negative")
    if args.evidence_out:
        missing_gate_args = [
            f"--{name.replace('_', '-')}"
            for name in (
                "min_candidate_pass_rate",
                "max_candidate_failures",
                "min_mean_speedup",
                "min_p95_speedup",
            )
            if getattr(args, name) is None
        ]
        if missing_gate_args:
            parser.error(
                "; ".join(f"{name} is required with --evidence-out" for name in missing_gate_args)
            )
    return args


def is_pass(row):
    if row.get("status") != "ok":
        return False
    trace_status = row.get("traceStatus")
    return trace_status in (None, "passed")


def p95(durations):
    if not durations:
        return 0
    ordered = sorted(durations)
    index = max(0, math.ceil(len(ordered) * 0.95) - 1)
    return ordered[index]


def read_rows(path):
    rows = []
    with Path(path).open(encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError as exc:
                raise SystemExit(f"{path}:{line_number}: invalid json: {exc}") from exc
            if not isinstance(row, dict):
                raise SystemExit(f"{path}:{line_number}: expected object row")
            rows.append(row)
    return rows


def summarize(tool, rows):
    durations = [int(row.get("durationMs", 0)) for row in rows]
    failures = [row for row in rows if not is_pass(row)]
    passed = len(rows) - len(failures)
    pass_rate = (passed / len(rows) * 100.0) if rows else 0.0
    mean_ms = round(statistics.mean(durations)) if durations else 0
    return {
        "tool": tool,
        "runs": len(rows),
        "passed": passed,
        "failures": len(failures),
        "passRate": pass_rate,
        "meanMs": mean_ms,
        "p95Ms": p95(durations),
    }


def ratio(baseline_value, candidate_value):
    if baseline_value <= 0 or candidate_value <= 0:
        return None
    return baseline_value / candidate_value


def percent_delta(candidate_value, baseline_value):
    if baseline_value <= 0:
        return None
    return ((candidate_value - baseline_value) / baseline_value) * 100.0


def comparison(candidate, baseline):
    return {
        "candidate": candidate,
        "baseline": baseline,
        "meanSpeedup": ratio(baseline["meanMs"], candidate["meanMs"]),
        "p95Speedup": ratio(baseline["p95Ms"], candidate["p95Ms"]),
        "meanDeltaPct": percent_delta(candidate["meanMs"], baseline["meanMs"]),
        "p95DeltaPct": percent_delta(candidate["p95Ms"], baseline["p95Ms"]),
    }


def benchmark_context(candidate_rows, baseline_rows):
    rows = candidate_rows + baseline_rows
    context = {}
    problems = []
    for field in CONTEXT_FIELDS:
        values = [str(row.get(field, "")).strip() for row in rows]
        concrete = [value for value in values if value]
        unique = sorted(set(concrete))
        if len(concrete) != len(values):
            problems.append(f"{field} missing")
        elif len(unique) != 1:
            problems.append(f"{field} mismatch: {', '.join(unique)}")
        else:
            context[field] = unique[0]
    return {
        "sameContext": not problems,
        "context": context,
        "contextProblems": problems,
    }


def format_ratio(value):
    return "n/a" if value is None else f"{value:.2f}x"


def format_pct(value):
    return "n/a" if value is None else f"{value:+.1f}%"


def markdown_report(data):
    candidate = data["candidate"]
    baseline = data["baseline"]
    lines = [
        "# Benchmark Comparison",
        "",
        "| Tool | Runs | Pass rate | Failures | Mean ms | P95 ms |",
        "| --- | ---: | ---: | ---: | ---: | ---: |",
        f"| {candidate['tool']} | {candidate['runs']} | {candidate['passRate']:.2f}% | {candidate['failures']} | {candidate['meanMs']} | {candidate['p95Ms']} |",
        f"| {baseline['tool']} | {baseline['runs']} | {baseline['passRate']:.2f}% | {baseline['failures']} | {baseline['meanMs']} | {baseline['p95Ms']} |",
        "",
        f"- Mean speedup: {format_ratio(data['meanSpeedup'])} ({format_pct(data['meanDeltaPct'])} candidate vs baseline)",
        f"- P95 speedup: {format_ratio(data['p95Speedup'])} ({format_pct(data['p95DeltaPct'])} candidate vs baseline)",
        f"- Same benchmark context: {'yes' if data.get('sameContext') else 'no'}",
        "",
        "Interpretation: negative deltas mean the candidate was faster for that metric. Compare only runs collected on the same host, device state, app build, and scenario.",
    ]
    return "\n".join(lines) + "\n"


def gate_failures(data, args):
    failures = []
    candidate = data["candidate"]
    baseline = data["baseline"]
    if args.evidence_out and candidate["runs"] < 20:
        failures.append(f"candidateRuns {candidate['runs']} below minimum 20")
    if args.evidence_out and baseline["runs"] < 20:
        failures.append(f"baselineRuns {baseline['runs']} below minimum 20")
    if args.min_candidate_pass_rate is not None and candidate["passRate"] < args.min_candidate_pass_rate:
        failures.append(
            f"candidate passRate {candidate['passRate']:.2f}% below minimum {args.min_candidate_pass_rate:.2f}%"
        )
    if args.max_candidate_failures is not None and candidate["failures"] > args.max_candidate_failures:
        failures.append(
            f"candidate failures={candidate['failures']} above maximum {args.max_candidate_failures}"
        )
    if args.min_mean_speedup is not None:
        speedup = data["meanSpeedup"]
        if speedup is None or speedup < args.min_mean_speedup:
            actual = "n/a" if speedup is None else f"{speedup:.2f}x"
            failures.append(f"meanSpeedup {actual} below minimum {args.min_mean_speedup:.2f}x")
    if args.min_p95_speedup is not None:
        speedup = data["p95Speedup"]
        if speedup is None or speedup < args.min_p95_speedup:
            actual = "n/a" if speedup is None else f"{speedup:.2f}x"
            failures.append(f"p95Speedup {actual} below minimum {args.min_p95_speedup:.2f}x")
    if args.evidence_out and not data.get("sameContext"):
        details = "; ".join(data.get("contextProblems", [])) or "missing context"
        failures.append(f"same benchmark context evidence required ({details})")
    return failures


def write_evidence(args, data, failures, duration_ms):
    if not args.evidence_out:
        return
    path = Path(args.evidence_out)
    path.parent.mkdir(parents=True, exist_ok=True)
    row = {
        "name": "competitive benchmark comparison",
        "status": "failed" if failures else "passed",
        "durationMs": duration_ms,
        "command": " ".join(shlex.quote(part) for part in sys.argv),
        "candidate": args.candidate,
        "baseline": args.baseline,
        "results": args.results,
        "minCandidatePassRate": args.min_candidate_pass_rate,
        "maxCandidateFailures": args.max_candidate_failures,
        "minMeanSpeedup": args.min_mean_speedup,
        "minP95Speedup": args.min_p95_speedup,
        "candidateRuns": data["candidate"]["runs"],
        "baselineRuns": data["baseline"]["runs"],
        "candidatePassRate": data["candidate"]["passRate"],
        "candidateFailures": data["candidate"]["failures"],
        "meanSpeedup": data["meanSpeedup"],
        "p95Speedup": data["p95Speedup"],
        "sameContext": data["sameContext"],
        "context": data["context"],
    }
    if failures:
        row["error"] = "; ".join(failures)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(row, sort_keys=True, separators=(",", ":")) + "\n")


def main():
    started = time.monotonic()
    args = parse_args()
    rows = read_rows(args.results)
    by_tool = defaultdict(list)
    for row in rows:
        by_tool[str(row.get("tool", "unknown"))].append(row)

    missing = [tool for tool in (args.candidate, args.baseline) if tool not in by_tool]
    if missing:
        print(f"missing benchmark rows for: {', '.join(missing)}", file=sys.stderr)
        return 2

    data = comparison(
        summarize(args.candidate, by_tool[args.candidate]),
        summarize(args.baseline, by_tool[args.baseline]),
    )
    data.update(benchmark_context(by_tool[args.candidate], by_tool[args.baseline]))

    if args.format == "json":
        output = json.dumps(data, sort_keys=True) + "\n"
    else:
        output = markdown_report(data)

    if args.out:
        Path(args.out).write_text(output, encoding="utf-8")
    else:
        sys.stdout.write(output)

    failures = gate_failures(data, args)
    duration_ms = round((time.monotonic() - started) * 1000)
    write_evidence(args, data, failures, duration_ms)
    if failures:
        for failure in failures:
            print(f"benchmark comparison gate failed: {failure}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
