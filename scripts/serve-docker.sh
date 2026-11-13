#!/usr/bin/env bash
# Step B: serve a Ministral 3 model with vLLM in plain Docker (no Kubernetes yet), to validate GPU + image + model.
# Usage: scripts/serve-docker.sh [model]   (default: the 3B; try the 8B once the 3B works)
set -euo pipefail

MODEL="${1:-mistralai/Ministral-3-3B-Instruct-2512}"
VLLM_IMAGE="vllm/vllm-openai:v0.32.0"   # pinned, never :latest

# --gpus all                  give the container the GPU (NVIDIA Container Toolkit)
# --ipc=host                  PyTorch uses shared memory between processes; Docker's default 64 MB is too small
# -v ~/.cache/huggingface     keep the downloaded weights on the host, so a restart does not download them again
# --*-format mistral          load Mistral's native files (consolidated.safetensors, tekken tokenizer), per the model card
# --max-model-len 8192        the default context (262k tokens) would reserve far more KV cache than this GPU has
# --gpu-memory-utilization    fraction of the 16 GB vLLM may take; Windows already holds ~4 GB for the display
exec docker run --rm --name vllm --gpus all --ipc=host -p 8000:8000 \
  -v "$HOME/.cache/huggingface:/root/.cache/huggingface" \
  "$VLLM_IMAGE" \
  "$MODEL" \
  --tokenizer-mode mistral --config-format mistral --load-format mistral \
  --max-model-len 8192 \
  --gpu-memory-utilization 0.6
