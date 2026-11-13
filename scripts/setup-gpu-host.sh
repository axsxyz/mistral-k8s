#!/usr/bin/env bash
# Step E, host side: let kind nodes (which are Docker containers) receive the GPU.
# Same setup as NVIDIA's nvkind (github.com/NVIDIA/nvkind, "Setup").
# Run with: sudo bash scripts/setup-gpu-host.sh
set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }

# 1. Make "nvidia" Docker's default runtime (kind cannot pass --gpus to its node containers), with CDI enabled.
nvidia-ctk runtime configure --runtime=docker --set-as-default --cdi.enabled

# 2. Feature flag: a container that mounts /dev/null on /var/run/nvidia-container-devices/all gets every GPU.
#    kind can declare that mount on a node (extraMounts), which is how the GPU reaches the node.
nvidia-ctk config --set accept-nvidia-visible-devices-as-volume-mounts=true --in-place

systemctl restart docker

echo "== Check: the GPU through the volume-mount trigger (no --gpus flag)"
docker run --rm -v /dev/null:/var/run/nvidia-container-devices/all ubuntu:24.04 nvidia-smi -L
