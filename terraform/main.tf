# Terraform manages what runs *inside* the cluster: the namespace and the Helm release of the model server.
# The kind cluster itself is created by kind (kind/cluster.yaml); on a cloud this file would sit next to the cluster's
# own resources (EKS, GKE, AKS...) and read their credentials instead of a local kubeconfig.

provider "kubernetes" {
  config_path    = pathexpand(var.kubeconfig_path)
  config_context = var.kube_context
}

provider "helm" {
  kubernetes = {
    config_path    = pathexpand(var.kubeconfig_path)
    config_context = var.kube_context
  }
}

locals {
  chart_dir = "${path.module}/../charts/ministral"
  # The GPU profile layers values-gpu.yaml over the chart defaults (which are the CPU profile).
  values_files = concat(
    var.profile == "gpu" ? ["${local.chart_dir}/values-gpu.yaml"] : [],
    var.extra_values_files,
  )
}

resource "kubernetes_namespace_v1" "mistral" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# --- GPU profile only -------------------------------------------------------------------------------------------------

# The device plugin's DaemonSet only runs on nodes labelled as having an NVIDIA GPU. On a real cluster, Node Feature
# Discovery or the GPU Operator sets this label; on kind we set it ourselves.
resource "kubernetes_labels" "gpu_node" {
  count       = var.profile == "gpu" ? 1 : 0
  api_version = "v1"
  kind        = "Node"
  metadata {
    name = var.gpu_node
  }
  labels = {
    "nvidia.com/gpu.present" = "true"
  }
}

# NVIDIA device plugin: advertises nvidia.com/gpu to the kubelet. Its WSL2 mode (since v0.19.1) reports one "all"
# device backed by /dev/dxg.
resource "helm_release" "nvidia_device_plugin" {
  count            = var.profile == "gpu" ? 1 : 0
  name             = "nvidia-device-plugin"
  namespace        = "nvidia-device-plugin"
  create_namespace = true
  repository       = "https://nvidia.github.io/k8s-device-plugin"
  chart            = "nvidia-device-plugin"
  version          = "0.20.1"
  wait             = true

  depends_on = [kubernetes_labels.gpu_node]
}

# --- Monitoring (optional) --------------------------------------------------------------------------------------------

# Prometheus Operator + Prometheus + Grafana. Installed before the model server so that the ServiceMonitor CRD exists
# when the model's chart renders its ServiceMonitor.
resource "helm_release" "monitoring" {
  count            = var.monitoring ? 1 : 0
  name             = "monitoring"
  namespace        = "monitoring"
  create_namespace = true
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "92.16.1"
  values           = [file("${path.module}/../observability/kube-prometheus-stack-values.yaml")]
  wait             = true
  timeout          = 600
}

# The vLLM dashboard, picked up by Grafana's sidecar through the grafana_dashboard label.
resource "kubernetes_config_map_v1" "vllm_dashboard" {
  count = var.monitoring ? 1 : 0
  metadata {
    name      = "vllm-dashboard"
    namespace = "monitoring"
    labels    = { grafana_dashboard = "1" }
  }
  data = {
    "vllm-dashboard.json" = file("${path.module}/../observability/vllm-dashboard.json")
  }
  depends_on = [helm_release.monitoring]
}

# --- Model server -----------------------------------------------------------------------------------------------------

resource "helm_release" "ministral" {
  name      = "ministral"
  namespace = kubernetes_namespace_v1.mistral.metadata[0].name
  chart     = local.chart_dir

  values = [for f in local.values_files : file(f)]

  set = [
    { name = "metrics.serviceMonitor.enabled", value = tostring(var.monitoring) },
  ]

  # The GPU must be advertised before the pod can be scheduled; the ServiceMonitor CRD must exist before it is rendered.
  depends_on = [helm_release.nvidia_device_plugin, helm_release.monitoring]

  # Wait until the Deployment is available: the first start downloads the weights and loads the model.
  wait    = true
  timeout = 1200
}
