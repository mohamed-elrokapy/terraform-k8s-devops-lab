variable "kubeconfig_path" {
  description = "Path to the kubeconfig file."
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "kubeconfig context to use. Set to null to use the kubeconfig's current context."
  type        = string
  default     = "kind-tfk8s-lab"
}

variable "namespace" {
  description = "Namespace to create and deploy into."
  type        = string
  default     = "devops-lab"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid DNS label (lowercase a-z, 0-9, hyphen, max 63 characters)."
  }
}

variable "image" {
  description = "Container image with an explicit tag (not :latest). For kind, build it locally and load it with `make image`."
  type        = string
  default     = "labapi:dev"

  validation {
    condition     = can(regex(":[^:/]+$", var.image)) && !endswith(var.image, ":latest")
    error_message = "image must include an explicit tag and must not use :latest."
  }
}

variable "image_pull_policy" {
  description = "imagePullPolicy. Keep IfNotPresent for kind-loaded images; use Always for a registry with mutable tags."
  type        = string
  default     = "IfNotPresent"

  validation {
    condition     = contains(["Always", "IfNotPresent", "Never"], var.image_pull_policy)
    error_message = "image_pull_policy must be Always, IfNotPresent or Never."
  }
}

variable "app_version" {
  description = "Version string shown by /version."
  type        = string
  default     = "dev"
}

variable "replicas" {
  description = "Initial replica count (the HPA owns it afterwards if enabled)."
  type        = number
  default     = 2

  validation {
    condition     = var.replicas >= 1 && var.replicas <= 10 && floor(var.replicas) == var.replicas
    error_message = "replicas must be a whole number between 1 and 10."
  }
}

variable "dns_stub" {
  description = "Run the app with DNS_STUB=true (built-in DNS table). For CI and offline demos only."
  type        = bool
  default     = false
}

variable "wait_for_rollout" {
  description = "Wait for the Deployment rollout to finish during apply."
  type        = bool
  default     = true
}

variable "enable_hpa" {
  description = "Create the HorizontalPodAutoscaler. It needs metrics-server to act (`make metrics-server` on kind)."
  type        = bool
  default     = true
}

variable "hpa_min_replicas" {
  description = "HPA minimum replicas."
  type        = number
  default     = 2
}

variable "hpa_max_replicas" {
  description = "HPA maximum replicas."
  type        = number
  default     = 5
}

variable "enable_pdb" {
  description = "Create the PodDisruptionBudget."
  type        = bool
  default     = true
}

variable "enable_network_policy" {
  description = "Create the default-deny ingress NetworkPolicy and the allow rule."
  type        = bool
  default     = true
}

variable "ingress_controller_namespace" {
  description = "Namespace of the ingress controller, allowed through the NetworkPolicy."
  type        = string
  default     = "ingress-nginx"
}

variable "enable_ingress" {
  description = "Create an nginx Ingress (needs an ingress controller, see `make ingress`)."
  type        = bool
  default     = false
}

variable "ingress_host" {
  description = "Host name for the Ingress. *.localtest.me resolves to 127.0.0.1."
  type        = string
  default     = "lab.localtest.me"
}
