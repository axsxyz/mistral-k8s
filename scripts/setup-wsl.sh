#!/usr/bin/env bash
# One-time host setup on WSL2 Ubuntu 24.04: native Docker Engine + NVIDIA Container Toolkit.
# Why native Docker instead of Docker Desktop: the GPU-in-kind step needs the NVIDIA runtime configured in the Docker
# daemon that runs the kind nodes, which Docker Desktop does not let you configure.
# Run with: sudo bash scripts/setup-wsl.sh
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "run with sudo"; exit 1; }
TARGET_USER="${SUDO_USER:?run through sudo, not as root directly}"

echo "== Docker Engine (official apt repository)"
apt-get update
apt-get install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
# shellcheck source=/dev/null
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list

echo "== NVIDIA Container Toolkit (official apt repository)"
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | gpg --dearmor --yes -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  > /etc/apt/sources.list.d/nvidia-container-toolkit.list

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin nvidia-container-toolkit

echo "== Register the NVIDIA runtime in Docker and restart"
nvidia-ctk runtime configure --runtime=docker
systemctl enable --now docker
systemctl restart docker

echo "== Let $TARGET_USER use docker without sudo"
usermod -aG docker "$TARGET_USER"

echo "== Check"
docker version --format 'Docker Engine {{.Server.Version}}'
if command -v nvidia-smi >/dev/null; then
  docker run --rm --gpus all nvidia/cuda:12.8.0-base-ubuntu24.04 nvidia-smi
else
  echo "No NVIDIA GPU detected: Docker is ready for the CPU profile."
fi
