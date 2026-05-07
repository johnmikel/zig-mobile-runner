#!/usr/bin/env python3
import argparse
import json
import math
import statistics
import sys
from collections import defaultdict
from pathlib import Path


def parse_args():
    parser = argparse.ArgumentParser(description="Gate benchmark results by pass rate and duration thresholds.")
    parser.add_argument("--results", required=True, help="Path to benchmark results.jsonl.")
    parser.add_argument("--min-pass-rate", type=float, default=None, help="Minimum pass rate percentage, for example 100.")
    parser.add_argument("--max-failures", type=int, default=None, help="Maximum allowed failed runs.")
    parser.add_argument("--max-mean-ms", type=int, default=None, help="Maximum allowed mean duration in ms.")
    parser.add_argument("--max-p95-ms", type=int, default=None, help="Maximum allowed p95 duration in ms.")
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
    p95_ms = p95(durations)
    return {
        "tool": tool,
        "runs": len(rows),
        "passed": passed,
        "failures": len(failures),
        "passRate": pass_rate,
        "meanMs": mean_ms,
        "p95Ms": p95_ms,
        "failureRows": failures,
    }


def format_summary(summary):
    return (
        f"{summary['tool']}: runs={summary['runs']} "
        f"passRate={summary['passRate']:.2f}% failures={summary['failures']} "
        f"meanMs={summary['meanMs']} p95Ms={summary['p95Ms']}"
    )


def violations(summary, args):
    problems = []
    if args.min_pass_rate is not None and summary["passRate"] < args.min_pass_rate:
        problems.append(f"passRate {summary['passRate']:.2f}% < {args.min_pass_rate:.2f}%")
    if args.max_failures is not None and summary["failures"] > args.max_failures:
        problems.append(f"failures {summary['failures']} > {args.max_failures}")
    if args.max_mean_ms is not None and summary["meanMs"] > args.max_mean_ms:
        problems.append(f"meanMs {summary['meanMs']} > {args.max_mean_ms}")
    if args.max_p95_ms is not None and summary["p95Ms"] > args.max_p95_ms:
        problems.append(f"p95Ms {summary['p95Ms']} > {args.max_p95_ms}")
    return problems


def main():
    args = parse_args()
    rows = read_rows(args.results)
    if not rows:
        print(f"no benchmark rows found: {args.results}", file=sys.stderr)
        return 2

    by_tool = defaultdict(list)
    for row in rows:
        by_tool[str(row.get("tool", "unknown"))].append(row)

    failed = False
    for tool in sorted(by_tool):
        summary = summarize(tool, by_tool[tool])
        print(format_summary(summary))
        problems = violations(summary, args)
        for problem in problems:
            print(f"gate failed for {tool}: {problem}", file=sys.stderr)
        failed = failed or bool(problems)

    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
