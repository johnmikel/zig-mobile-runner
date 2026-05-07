#!/usr/bin/env python3
import argparse
import json
import math
import statistics
import sys
from collections import defaultdict
from pathlib import Path


def parse_args():
    parser = argparse.ArgumentParser(description="Compare benchmark JSONL rows for two runner labels.")
    parser.add_argument("--results", required=True, help="Path to a benchmark results.jsonl file.")
    parser.add_argument("--candidate", default="zmr", help="Candidate tool label. Default: zmr.")
    parser.add_argument("--baseline", required=True, help="Baseline tool label to compare against.")
    parser.add_argument("--format", choices=("markdown", "json"), default="markdown", help="Output format.")
    parser.add_argument("--out", help="Optional output file. Defaults to stdout.")
    return parser.parse_args()


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
        "",
        "Interpretation: negative deltas mean the candidate was faster for that metric. Compare only runs collected on the same host, device state, app build, and scenario.",
    ]
    return "\n".join(lines) + "\n"


def main():
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

    if args.format == "json":
        output = json.dumps(data, sort_keys=True) + "\n"
    else:
        output = markdown_report(data)

    if args.out:
        Path(args.out).write_text(output, encoding="utf-8")
    else:
        sys.stdout.write(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
