#!/usr/bin/env bash
# Run the load test Job and save each concurrency level's raw result to bench/results/<date>/c<N>.json.
# Usage: bench/run.sh
set -euo pipefail
cd "$(dirname "$0")"
OUT="results/$(date -u +%Y-%m-%d)"
mkdir -p "$OUT"

kubectl -n mistral delete job vllm-bench --ignore-not-found --wait
kubectl apply -f job.yaml
kubectl -n mistral wait --for=condition=complete job/vllm-bench --timeout=45m \
  || { kubectl -n mistral logs job/vllm-bench --tail=50; exit 1; }

kubectl -n mistral logs job/vllm-bench > "$OUT/bench.log"
grep '^RESULT_JSON ' "$OUT/bench.log" | sed 's/^RESULT_JSON //' | while read -r line; do
  c=$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["max_concurrency"])' <<<"$line")
  python3 -m json.tool <<<"$line" > "$OUT/c$c.json"
done
ls -1 "$OUT"
python3 summarize.py "$OUT"
