"""Summarize vllm bench serve results: a Markdown table on stdout and an SVG chart next to the results.

Usage: python3 bench/summarize.py bench/results/<date>
Standard library only. Field names are the ones vllm v0.32.0 writes (vllm/benchmarks/serve.py).
"""

import json
import math
import sys
from pathlib import Path


def load(result_dir: Path) -> list[dict]:
    """Closed-loop runs (max_concurrency set) sorted by concurrency, then open-loop bursts by size."""
    runs = [json.loads(p.read_text()) for p in result_dir.glob("*.json") if p.name != "server-metrics.json"]
    return sorted(runs, key=lambda r: (r["max_concurrency"] is None, r["max_concurrency"] or r["num_prompts"]))


def label(r: dict) -> str:
    return str(r["max_concurrency"]) if r["max_concurrency"] else f"burst of {r['num_prompts']}"


def table(runs: list[dict]) -> str:
    rows = [
        "| Load | Requests (failed) | Output tok/s | Req/s | TTFT p50 / p95 (ms) | TPOT p50 / p95 (ms) | E2E p95 (s) |",
        "|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for r in runs:
        rows.append(
            f"| {label(r)} | {r['completed']} ({r['failed']}) | {r['output_throughput']:.0f} "
            f"| {r['request_throughput']:.2f} | {r['median_ttft_ms']:,.0f} / {r['p95_ttft_ms']:,.0f} "
            f"| {r['median_tpot_ms']:.1f} / {r['p95_tpot_ms']:.1f} | {r['p95_e2el_ms'] / 1000:.1f} |"
        )
    return "\n".join(rows)


def nice_ceiling(v: float) -> float:
    """Smallest of 1, 2, 2.5, 4, 5, 8, 10 x 10^k at or above v, so the four grid steps land on round numbers."""
    if v <= 0:
        return 1
    k = 10 ** math.floor(math.log10(v))
    return next(m * k for m in (1, 2, 2.5, 4, 5, 8, 10) if m * k >= v)


def line_chart(x0: int, title: str, xs: list[int], ys: list[float], unit: str, color: str) -> str:
    """One 420x260 panel: polyline over evenly spaced concurrency levels, y axis from 0."""
    w, h, left, right, top, bottom = 420, 260, 56, 16, 40, 44
    pw, ph = w - left - right, h - top - bottom
    ymax = nice_ceiling(max(ys) * 1.12)
    px = lambda i: x0 + left + (pw * i / max(len(xs) - 1, 1))
    py = lambda v: top + ph - ph * v / ymax
    out = [f'<text x="{x0 + left}" y="24" class="t">{title}</text>']
    for k in range(5):  # horizontal grid + y labels
        v = ymax * k / 4
        out.append(f'<line x1="{x0 + left}" x2="{x0 + left + pw}" y1="{py(v):.1f}" y2="{py(v):.1f}" class="g"/>')
        out.append(f'<text x="{x0 + left - 8}" y="{py(v) + 4:.1f}" class="a" text-anchor="end">{v:.0f}</text>')
    for i, c in enumerate(xs):
        out.append(f'<text x="{px(i):.1f}" y="{top + ph + 18}" class="a" text-anchor="middle">{c}</text>')
    out.append(f'<text x="{x0 + left + pw / 2}" y="{h - 6}" class="a" text-anchor="middle">concurrent requests</text>')
    pts = " ".join(f"{px(i):.1f},{py(v):.1f}" for i, v in enumerate(ys))
    out.append(f'<polyline points="{pts}" fill="none" stroke="{color}" stroke-width="2.5"/>')
    for i, v in enumerate(ys):
        out.append(f'<circle cx="{px(i):.1f}" cy="{py(v):.1f}" r="4" fill="{color}"/>')
        out.append(f'<text x="{px(i):.1f}" y="{py(v) - 10:.1f}" class="v" text-anchor="middle">{v:.0f}</text>')
    out.append(f'<text x="{x0 + left}" y="{top - 6}" class="a">{unit}</text>')
    return "\n".join(out)


def svg(runs: list[dict]) -> str:
    runs = [r for r in runs if r["max_concurrency"]]  # the chart's x axis is concurrency: closed-loop runs only
    xs = [r["max_concurrency"] for r in runs]
    body = line_chart(0, "Output throughput", xs, [r["output_throughput"] for r in runs], "tokens/s", "#2a6fdb")
    body += line_chart(420, "Time to first token, p95", xs, [r["p95_ttft_ms"] for r in runs], "ms", "#d9480f")
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="840" height="260" viewBox="0 0 840 260" '
        'font-family="system-ui, -apple-system, Segoe UI, sans-serif">\n'
        "<style>.t{font-size:15px;font-weight:600;fill:#1f2328}.a{font-size:11px;fill:#59636e}"
        ".v{font-size:11px;font-weight:600;fill:#1f2328}.g{stroke:#d1d9e0;stroke-width:1}</style>\n"
        '<rect width="840" height="260" fill="#ffffff"/>\n' + body + "\n</svg>\n"
    )


if __name__ == "__main__":
    result_dir = Path(sys.argv[1])
    runs = load(result_dir)
    if not runs:
        sys.exit(f"no result JSON in {result_dir}")
    if any(r["max_concurrency"] for r in runs):
        (result_dir / "throughput-latency.svg").write_text(svg(runs))
    print(table(runs))
