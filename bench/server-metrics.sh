#!/usr/bin/env bash
# Server-side view of a load-test run, from Prometheus, over the Job's exact start-to-completion window:
# peak running/waiting requests, peak KV cache usage, preemptions, CPU of the client and of the server.
# Writes <result dir>/server-metrics.json. Needs the monitoring profile (var.monitoring = true).
# Usage: bench/server-metrics.sh bench/results/<date>-<name>
set -euo pipefail
OUT="${1:?usage: $0 <result dir>}"

START=$(kubectl -n mistral get job vllm-bench -o jsonpath='{.status.startTime}')
END=$(kubectl -n mistral get job vllm-bench -o jsonpath='{.status.completionTime}')
[ -n "$END" ] || { echo "job vllm-bench has not completed"; exit 1; }

kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 19090:9090 >/dev/null 2>&1 &
PF=$!
trap 'kill $PF' EXIT
sleep 3

python3 - "$START" "$END" "$OUT/server-metrics.json" <<'EOF'
import json, sys, urllib.parse, urllib.request
from datetime import datetime

start, end, path = sys.argv[1:4]
t0 = datetime.fromisoformat(start.replace("Z", "+00:00"))
t1 = datetime.fromisoformat(end.replace("Z", "+00:00"))
window = f"{int((t1 - t0).total_seconds())}s"

def query(expr: str) -> float | None:
    url = "http://localhost:19090/api/v1/query?" + urllib.parse.urlencode({"query": expr, "time": t1.timestamp()})
    result = json.load(urllib.request.urlopen(url))["data"]["result"]
    return round(float(result[0]["value"][1]), 3) if result else None

cpu = 'rate(container_cpu_usage_seconds_total{{namespace="mistral",container="{c}"}}[1m])'
metrics = {
    "window": {"start": start, "end": end, "seconds": int((t1 - t0).total_seconds())},
    "max_requests_running": query(f"max_over_time(vllm:num_requests_running[{window}])"),
    "max_requests_waiting": query(f"max_over_time(vllm:num_requests_waiting[{window}])"),
    "max_kv_cache_usage": query(f"max_over_time(vllm:kv_cache_usage_perc[{window}])"),
    "preemptions": query(f"sum(increase(vllm:num_preemptions_total[{window}]))"),
    "requests_finished": query(f"sum(increase(vllm:request_success_total[{window}]))"),
    "max_client_cpu_cores": query(f"max_over_time({cpu.format(c='bench')}[{window}:15s])"),
    "max_server_cpu_cores": query(f"max_over_time({cpu.format(c='server')}[{window}:15s])"),
}
json.dump(metrics, open(path, "w"), indent=2)
print(json.dumps(metrics, indent=2))

# Time series over the same window, one point every 5 s, for bench/timeline.py.
def series(expr: str) -> list[list[float]]:
    params = {"query": expr, "start": t0.timestamp(), "end": t1.timestamp(), "step": "5"}
    url = "http://localhost:19090/api/v1/query_range?" + urllib.parse.urlencode(params)
    result = json.load(urllib.request.urlopen(url))["data"]["result"]
    return [[round(float(t) - t0.timestamp(), 1), round(float(v), 3)] for t, v in result[0]["values"]] if result else []

timeline = {
    "requests_waiting": series("sum(vllm:num_requests_waiting)"),
    "requests_running": series("sum(vllm:num_requests_running)"),
    "generation_tokens_per_s": series("sum(rate(vllm:generation_tokens_total[10s]))"),
    "kv_cache_usage": series("max(vllm:kv_cache_usage_perc)"),
}
json.dump(timeline, open(path.replace("server-metrics.json", "timeline.json"), "w"))
EOF
