"""Draw a run's server-side timeline (from bench/server-metrics.sh) as an SVG: queue depth and output throughput.

Usage: python3 bench/timeline.py bench/results/<date>-<name>
Reads timeline.json, writes timeline.svg next to it. Standard library only.
"""

import json
import sys
from pathlib import Path

from summarize import nice_ceiling


def panel(x0: int, title: str, unit: str, points: list[list[float]], color: str, fmt) -> str:
    w, h, left, right, top, bottom = 420, 260, 60, 14, 44, 40
    pw, ph = w - left - right, h - top - bottom
    tmax = max(t for t, _ in points) or 1
    ymax = nice_ceiling(max(v for _, v in points) * 1.1)
    px = lambda t: x0 + left + pw * t / tmax
    py = lambda v: top + ph - ph * v / ymax
    out = [f'<text x="{x0 + left}" y="22" class="t">{title}</text>',
           f'<text x="{x0 + left}" y="{top - 8}" class="a">{unit}</text>']
    for k in range(5):
        v = ymax * k / 4
        out.append(f'<line x1="{x0 + left}" x2="{x0 + left + pw}" y1="{py(v):.1f}" y2="{py(v):.1f}" class="g"/>')
        out.append(f'<text x="{x0 + left - 8}" y="{py(v) + 4:.1f}" class="a" text-anchor="end">{fmt(v)}</text>')
    for m in range(0, int(tmax // 60) + 1, 2):  # a tick every 2 minutes
        out.append(f'<text x="{px(m * 60):.1f}" y="{top + ph + 16}" class="a" text-anchor="middle">{m}</text>')
    out.append(f'<text x="{x0 + left + pw / 2}" y="{h - 6}" class="a" text-anchor="middle">minutes since the Job started</text>')
    line = " ".join(f"{px(t):.1f},{py(v):.1f}" for t, v in points)
    area = f"{px(points[0][0]):.1f},{py(0):.1f} {line} {px(points[-1][0]):.1f},{py(0):.1f}"
    out.append(f'<polygon points="{area}" fill="{color}" fill-opacity="0.15"/>')
    out.append(f'<polyline points="{line}" fill="none" stroke="{color}" stroke-width="2"/>')
    return "\n".join(out)


if __name__ == "__main__":
    result_dir = Path(sys.argv[1])
    tl = json.loads((result_dir / "timeline.json").read_text())
    body = panel(0, "Requests waiting in the queue", "requests", tl["requests_waiting"], "#d9480f",
                 lambda v: f"{v:,.0f}")
    body += panel(420, "Output throughput", "tokens/s", tl["generation_tokens_per_s"], "#2a6fdb",
                  lambda v: f"{v:,.0f}")
    (result_dir / "timeline.svg").write_text(
        '<svg xmlns="http://www.w3.org/2000/svg" width="840" height="260" viewBox="0 0 840 260" '
        'font-family="system-ui, -apple-system, Segoe UI, sans-serif">\n'
        "<style>.t{font-size:15px;font-weight:600;fill:#1f2328}.a{font-size:11px;fill:#59636e}"
        ".g{stroke:#d1d9e0;stroke-width:1}</style>\n"
        '<rect width="840" height="260" fill="#ffffff"/>\n' + body + "\n</svg>\n"
    )
    print(f"wrote {result_dir / 'timeline.svg'}")
