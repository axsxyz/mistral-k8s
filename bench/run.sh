#!/usr/bin/env bash
# Run the load-test Job and save each level's raw result to bench/results/<date>-<name>/.
# Usage:
#   bench/run.sh                                  baseline: concurrency 1 4 8 16 32
#   bench/run.sh stress "64 128 256 512 1024" 4   name, levels, requests per unit of concurrency
#   bench/run.sh burst "burst10000"               10,000 requests fired at once
set -euo pipefail
cd "$(dirname "$0")"
NAME="${1:-baseline}"
LEVELS="${2:-1 4 8 16 32}"
REQ_FACTOR="${3:-8}"
OUT="results/$(date -u +%Y-%m-%d)-$NAME"
mkdir -p "$OUT"

kubectl -n mistral delete job vllm-bench --ignore-not-found --wait
# Fill the BENCH_* values of job.yaml, then create the Job.
python3 - "$LEVELS" "$REQ_FACTOR" <<'EOF' | kubectl apply -f -
import sys, re
levels, factor = sys.argv[1], sys.argv[2]
text = open("job.yaml").read()
text = re.sub(r'(name: BENCH_LEVELS\n\s+value: )".*"', rf'\1"{levels}"', text)
text = re.sub(r'(name: BENCH_REQ_FACTOR\n\s+value: )".*"', rf'\1"{factor}"', text)
sys.stdout.write(text)
EOF
echo "levels: $LEVELS (x$REQ_FACTOR requests); follow with: kubectl -n mistral logs -f job/vllm-bench"
kubectl -n mistral wait --for=condition=complete job/vllm-bench --timeout=90m \
  || { kubectl -n mistral logs job/vllm-bench --tail=50; exit 1; }

kubectl -n mistral logs job/vllm-bench > "$OUT/bench.log"
grep '^RESULT_JSON ' "$OUT/bench.log" | sed 's/^RESULT_JSON //' | while read -r line; do
  level=$(python3 -c 'import json,sys; r=json.loads(sys.stdin.read()); print(r["max_concurrency"] or "burst%d" % r["num_prompts"])' <<<"$line")
  python3 -m json.tool <<<"$line" > "$OUT/$level.json"
done
ls -1 "$OUT"
python3 summarize.py "$OUT"
# Server-side view from Prometheus, when the monitoring profile is installed.
if kubectl -n monitoring get svc monitoring-kube-prometheus-prometheus >/dev/null 2>&1; then
  bash server-metrics.sh "$OUT"
  python3 timeline.py "$OUT"
fi
