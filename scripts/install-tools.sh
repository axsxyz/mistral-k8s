#!/usr/bin/env bash
# Step C: install the Kubernetes tooling into ~/.local/bin (no sudo). Versions are pinned and every download is
# checked against the checksum its project publishes.
set -euo pipefail

KIND_VERSION=v0.33.0
KUBECTL_VERSION=v1.37.1      # within one minor of the cluster (kind v0.33 default node: v1.37.0)
HELM_VERSION=v4.3.1
TERRAFORM_VERSION=1.17.0

BIN="$HOME/.local/bin"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$BIN"
cd "$TMP"

verify() { # verify <file> <expected sha256>
  echo "$2  $1" | sha256sum --check --strict
}

echo "== kind $KIND_VERSION"
curl -fsSLo kind "https://kind.sigs.k8s.io/dl/$KIND_VERSION/kind-linux-amd64"
verify kind "$(curl -fsSL "https://kind.sigs.k8s.io/dl/$KIND_VERSION/kind-linux-amd64.sha256sum" | cut -d' ' -f1)"
install -m 0755 kind "$BIN/kind"

echo "== kubectl $KUBECTL_VERSION"
curl -fsSLo kubectl "https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/amd64/kubectl"
verify kubectl "$(curl -fsSL "https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/amd64/kubectl.sha256")"
install -m 0755 kubectl "$BIN/kubectl"

echo "== helm $HELM_VERSION"
curl -fsSLO "https://get.helm.sh/helm-$HELM_VERSION-linux-amd64.tar.gz"
verify "helm-$HELM_VERSION-linux-amd64.tar.gz" \
  "$(curl -fsSL "https://get.helm.sh/helm-$HELM_VERSION-linux-amd64.tar.gz.sha256sum" | cut -d' ' -f1)"
tar -xzf "helm-$HELM_VERSION-linux-amd64.tar.gz"
install -m 0755 linux-amd64/helm "$BIN/helm"

echo "== terraform $TERRAFORM_VERSION"
ZIP="terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
curl -fsSLO "https://releases.hashicorp.com/terraform/$TERRAFORM_VERSION/$ZIP"
verify "$ZIP" "$(curl -fsSL "https://releases.hashicorp.com/terraform/$TERRAFORM_VERSION/terraform_${TERRAFORM_VERSION}_SHA256SUMS" | grep " $ZIP\$" | cut -d' ' -f1)"
python3 -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extract('terraform')" "$ZIP"
install -m 0755 terraform "$BIN/terraform"

echo "== Installed"
kind version
kubectl version --client
helm version --short
terraform version | head -1
