variable "kubeconfig_path" {
  description = "kubeconfig file to use."
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "kubeconfig context of the target cluster (kind names it kind-<cluster name>)."
  type        = string
  default     = "kind-mistral"
}

variable "namespace" {
  description = "Namespace that holds the model server."
  type        = string
  default     = "mistral"
}

variable "profile" {
  description = "cpu = llama.cpp + GGUF Q4 on CPU; gpu = vLLM + FP8 weights on one NVIDIA GPU."
  type        = string
  default     = "cpu"

  validation {
    condition     = contains(["cpu", "gpu"], var.profile)
    error_message = "profile must be \"cpu\" or \"gpu\"."
  }
}
