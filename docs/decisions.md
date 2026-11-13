# Design decisions

Short records of each choice: the context, what I picked, and what would change on a production cluster.

## 1. Native Docker Engine in WSL2, not Docker Desktop

- **Context:** Docker Desktop failed to start: mounting its data disk returned `HCS/E_ACCESSDENIED`. The kind GPU step
  also needs the NVIDIA runtime set as the Docker daemon's *default* runtime, which Docker Desktop does not expose.
- **Decision:** Docker Engine from Docker's apt repository, plus the NVIDIA Container Toolkit, inside Ubuntu
  (`scripts/setup-wsl.sh`). This is the same setup as on a Linux GPU server.
- **In production:** nodes run containerd directly, with the NVIDIA GPU Operator or the toolkit baked into the node image.

## 2. kind for the cluster

- **Context:** this needs a real Kubernetes API on one machine, recreated cheaply, usable in CI.
- **Decision:** kind (Kubernetes in Docker), one node, node image pinned by digest (`kind/cluster.yaml`).
- **Trade-off:** node changes such as new mounts mean recreating the cluster. That is acceptable because everything
  in it is rebuilt by Terraform.
- **In production:** a managed cluster (EKS/GKE/AKS) or kubeadm/RKE2 on premises. The Terraform layout stays the same,
  with the cluster's own resources added next to it.

## 3. Two serving profiles with one chart

- **GPU: vLLM + FP8 weights.**
  - vLLM is the server Mistral documents for self-deployment. It provides continuous batching, paged KV cache and an
    OpenAI-compatible API.
  - Ministral 3 ships FP8 weights, so the 3B fits in ~4.5 GiB.
- **CPU: llama.cpp + Mistral's official GGUF Q4_K_M.**
  - It runs anywhere, including CI runners without GPUs.
  - The same templates exercise the same probes, volume and Service.
- **How:** the chart's defaults are the CPU profile, and `values-gpu.yaml` overrides the image, args, resources and
  GPU request.

## 4. Pin everything

- Tool versions are pinned in `scripts/install-tools.sh` and each download is checked against the project's published
  SHA-256.
- The kind node image, vLLM image and Terraform providers are pinned. The provider lock file is committed.
- llama.cpp stopped publishing per-build server tags at v1.0.0, so its image is pinned **by digest**. A tag can be moved
  to point elsewhere; a digest cannot.
- **Why:** reproducible rebuilds and a smaller supply-chain surface.

## 5. Probes sized for model servers

- **Context:** a model server is not ready for minutes on a cold start. Measured: vLLM needed 147 s of engine init after
  50 s of weight loading.
- **Problem:** a liveness probe alone would kill the container in a loop.
- **Decision:**
  - a **startupProbe** allows up to 10 min (60 × 10 s) and holds the other probes back until it passes;
  - **readiness** gates traffic;
  - **liveness** restarts a hung server.

## 6. Weights on a PersistentVolumeClaim, kept on uninstall

- **Decision:** weights download once into a PVC. A pod restart or replacement reuses them. The PVC carries
  `helm.sh/resource-policy: keep`, so `helm uninstall` / `terraform destroy` do not throw away gigabytes of weights.
- **Strategy:** `Recreate` rather than `RollingUpdate`. The volume is ReadWriteOnce, and one GPU cannot hold two
  servers during a rollout.
- **In production:**
  - a ReadWriteMany volume or object storage with a node-local cache;
  - weights pre-pulled into an image or a PVC snapshot, to cut cold starts;
  - several replicas behind the Service.

## 7. Terraform drives Helm

- **Decision:** Terraform owns the namespace and the `helm_release`, with a `profile` variable (`cpu` | `gpu`) that
  selects the values overlay. It works through `plan -out=tfplan` then `apply tfplan`, so what is applied is exactly
  what was reviewed.
- **In production:**
  - a remote state backend with locking;
  - plans posted on pull requests;
  - secrets (HF token) from a secret manager, never in the state or the repo.
