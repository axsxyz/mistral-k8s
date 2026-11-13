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
  values_files = var.profile == "gpu" ? ["${local.chart_dir}/values-gpu.yaml"] : []
}

resource "kubernetes_namespace_v1" "mistral" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "helm_release" "ministral" {
  name      = "ministral"
  namespace = kubernetes_namespace_v1.mistral.metadata[0].name
  chart     = local.chart_dir

  values = [for f in local.values_files : file(f)]

  # Wait until the Deployment is available: the first start downloads the weights and loads the model.
  wait    = true
  timeout = 1200
}
