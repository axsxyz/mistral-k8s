"""Compare two load-test runs level by level: a Markdown table on stdout and an SVG chart.

Usage: python3 bench/compare.py <run A dir> <run B dir> <label A> <label B> <out.svg>
Both runs must cover the same closed-loop concurrency levels. Standard library only.
"""

import json
import sys
from pathlib import Path

from summarize import load, nice_ceiling

COLORS = ("#8c959f", "#2a6fdb")  # A = before (grey), B = after (blue)


def by_level(result_dir: Path) -> dict[int, dict]:
    return {r["max_concurrency"]: r for r in load(result_dir) if r["max_concurrency"]}


def server(result_dir: Path) -> dict:
    p = result_dir / "server-metrics.json"
    return json.loads(p.read_text()) if p.exists() else {}


def pct(a: float, b: float) -> str:
    return f"{(b - a) / a * 100:+.0f}%"


def table(a: dict, b: dict, la: str, lb: str) -> str:
    rows = [
        f"| Concurrency | Output tok/s ({la} → {lb}) | TPOT p50 (ms) | TPOT p95 (ms) | TPOT p99 (ms) | TTFT p50 (s) | E2E p50 (s) |",
        "|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for c in sorted(a):
        x, y = a[c], b[c]
        rows.append(
            f"| {c} | {x['output_throughput']:.0f} → {y['output_throughput']:.0f} ({pct(x['output_throughput'], y['output_throughput'])}) "
            f"| {x['median_tpot_ms']:.1f} → {y['median_tpot_ms']:.1f} "
            f"| {x['p95_tpot_ms']:.1f} → **{y['p95_tpot_ms']:.1f}** ({pct(x['p95_tpot_ms'], y['p95_tpot_ms'])}) "
            f"| {x['p99_tpot_ms']:.1f} → {y['p99_tpot_ms']:.1f} "
            f"| {x['median_ttft_ms'] / 1000:.1f} → {y['median_ttft_ms'] / 1000:.1f} "
            f"| {x['median_e2el_ms'] / 1000:.1f} → {y['median_e2el_ms'] / 1000:.1f} |"
        )
    return "\n".join(rows)


def panel(x0: int, title: str, unit: str, levels: list[int], series: list[list[float]], fmt=lambda v: f"{v:.0f}") -> str:
    """Grouped bars: one group per concurrency level, one bar per run."""
    w, h, left, right, top, bottom = 420, 270, 56, 12, 44, 44
    pw, ph = w - left - right, h - top - bottom
    ymax = nice_ceiling(max(max(s) for s in series) * 1.15)
    py = lambda v: top + ph - ph * v / ymax
    group = pw / len(levels)
    bar = group * 0.32
    out = [f'<text x="{x0 + left}" y="22" class="t">{title}</text>',
           f'<text x="{x0 + left}" y="{top - 8}" class="a">{unit}</text>']
    for k in range(5):
        v = ymax * k / 4
        out.append(f'<line x1="{x0 + left}" x2="{x0 + left + pw}" y1="{py(v):.1f}" y2="{py(v):.1f}" class="g"/>')
        out.append(f'<text x="{x0 + left - 8}" y="{py(v) + 4:.1f}" class="a" text-anchor="end">{v:g}</text>')
    for i, c in enumerate(levels):
        gx = x0 + left + group * i + (group - 2 * bar - 4) / 2
        for j, s in enumerate(series):
            bx = gx + j * (bar + 4)
            out.append(f'<rect x="{bx:.1f}" y="{py(s[i]):.1f}" width="{bar:.1f}" height="{top + ph - py(s[i]):.1f}" '
                       f'fill="{COLORS[j]}" rx="2"/>')
            out.append(f'<text x="{bx + bar / 2:.1f}" y="{py(s[i]) - 4:.1f}" class="v" text-anchor="middle">{fmt(s[i])}</text>')
        out.append(f'<text x="{gx + bar + 2:.1f}" y="{top + ph + 16}" class="a" text-anchor="middle">{c}</text>')
    out.append(f'<text x="{x0 + left + pw / 2}" y="{h - 8}" class="a" text-anchor="middle">concurrent requests</text>')
    return "\n".join(out)


def svg(a: dict, b: dict, la: str, lb: str) -> str:
    levels = sorted(a)
    body = panel(0, "Time per output token, p95", "ms (lower is better)", levels,
                 [[a[c]["p95_tpot_ms"] for c in levels], [b[c]["p95_tpot_ms"] for c in levels]])
    body += panel(420, "Output throughput", "tokens/s", levels,
                  [[a[c]["output_throughput"] for c in levels], [b[c]["output_throughput"] for c in levels]],
                  fmt=lambda v: f"{v / 1000:.1f}k")
    legend = "".join(
        f'<rect x="{300 + i * 150}" y="281" width="12" height="12" fill="{COLORS[i]}" rx="2"/>'
        f'<text x="{318 + i * 150}" y="291" class="a">{lab}</text>'
        for i, lab in enumerate((la, lb))
    )
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="840" height="300" viewBox="0 0 840 300" '
        'font-family="system-ui, -apple-system, Segoe UI, sans-serif">\n'
        "<style>.t{font-size:15px;font-weight:600;fill:#1f2328}.a{font-size:11px;fill:#59636e}"
        ".v{font-size:10px;font-weight:600;fill:#1f2328}.g{stroke:#d1d9e0;stroke-width:1}</style>\n"
        '<rect width="840" height="300" fill="#ffffff"/>\n' + body + "\n" + legend + "\n</svg>\n"
    )


if __name__ == "__main__":
    dir_a, dir_b, label_a, label_b, out = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3], sys.argv[4], Path(sys.argv[5])
    a, b = by_level(dir_a), by_level(dir_b)
    if sorted(a) != sorted(b):
        sys.exit(f"levels differ: {sorted(a)} vs {sorted(b)}")
    out.write_text(svg(a, b, label_a, label_b))
    print(table(a, b, label_a, label_b))
    sa, sb = server(dir_a), server(dir_b)
    if sa and sb:
        print(f"\n| Server (Prometheus) | {label_a} | {label_b} |\n|---|---:|---:|")
        for key in ("max_requests_running", "max_requests_waiting", "max_kv_cache_usage", "preemptions",
                    "max_client_cpu_cores"):
            print(f"| {key} | {sa[key]:g} | {sb[key]:g} |")
