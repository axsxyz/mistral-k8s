#!/usr/bin/env bash
# Step E2: inside the kind node, install the NVIDIA Container Toolkit and make "nvidia" containerd's default runtime,
# so the pods the kubelet starts can receive the GPU the node itself received (kind/cluster-gpu.yaml).
# No sudo: everything runs through `docker exec` into the node container.
# Usage: scripts/setup-kind-gpu-node.sh [node container name]
set -euo pipefail
NODE="${1:-mistral-control-plane}"

echo "== GPU visible in the node?"
docker exec "$NODE" ls -l /dev/dxg
docker exec "$NODE" sh -c 'ls /usr/lib/wsl/lib | head -3'

echo "== NVIDIA Container Toolkit in the node (official apt repository)"
docker exec -e DEBIAN_FRONTEND=noninteractive "$NODE" bash -euo pipefail -c '
  apt-get update -qq
  apt-get install -y -qq curl gpg >/dev/null
  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
    | gpg --dearmor --yes -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
  curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
    | sed "s#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g" \
    > /etc/apt/sources.list.d/nvidia-container-toolkit.list
  apt-get update -qq
  apt-get install -y -qq nvidia-container-toolkit >/dev/null
'

echo "== nvidia as containerd default runtime, then restart containerd"
docker exec "$NODE" nvidia-ctk runtime configure --runtime=containerd --set-as-default --cdi.enabled
docker exec "$NODE" systemctl restart containerd

echo "== Check: nvidia-smi from inside the node"
# On WSL, nvidia-smi is one of the files injected from /usr/lib/wsl/lib, which is not on the node's PATH.
docker exec "$NODE" sh -c 'PATH="$PATH:/usr/lib/wsl/lib" nvidia-smi -L'
