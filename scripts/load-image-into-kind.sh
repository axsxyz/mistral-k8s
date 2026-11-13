#!/usr/bin/env bash
# Copy a local Docker image into the kind node's containerd, without a registry.
# Why not `kind load docker-image`: Docker 29's containerd image store keeps only the local platform's layers of a
# multi-platform image, while kind imports with --all-platforms, which fails with "content digest ...: not found".
# Exporting a single platform avoids it.
# Usage: scripts/load-image-into-kind.sh <image:tag> [node container name]
set -euo pipefail
IMAGE="${1:?usage: $0 <image:tag> [node]}"
NODE="${2:-mistral-control-plane}"

time docker save --platform linux/amd64 "$IMAGE" \
  | docker exec -i "$NODE" ctr --namespace=k8s.io images import --digests --snapshotter=overlayfs -

docker exec "$NODE" crictl images | grep -F "${IMAGE%%:*}"
