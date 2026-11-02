variable "name" {
  description = "Application name. Used for the Deployment, Service, ConfigMap and the app.kubernetes.io/name label."
  type        = string
  default     = "labapi"

  validation {
    condition     = can(regex("^[a-z]([-a-z0-9]{0,40}[a-z0-9])?$", var.name))
    error_message = "name must be a lowercase DNS label of at most 42 characters (a-z, 0-9, hyphen)."
  }
}

variable "namespace" {
  description = "Namespace to create and deploy into."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a valid DNS label (lowercase a-z, 0-9, hyphen, max 63 characters)."
  }
}

variable "pod_security_level" {
  description = "Pod Security Admission level enforced on the namespace."
  type        = string
  default     = "restricted"

  validation {
    condition     = contains(["privileged", "baseline", "restricted"], var.pod_security_level)
    error_message = "pod_security_level must be one of: privileged, baseline, restricted."
  }
}

variable "image" {
  description = "Container image including an explicit tag, for example labapi:dev."
  type        = string

  validation {
    condition     = can(regex(":[^:/]+$", var.image)) && !endswith(var.image, ":latest")
    error_message = "image must include an explicit tag and must not use :latest."
  }
}

variable "image_pull_policy" {
  description = "Kubernetes imagePullPolicy. IfNotPresent lets a kind-loaded local image be used without a registry."
  type        = string
  default     = "IfNotPresent"

  validation {
    condition     = contains(["Always", "IfNotPresent", "Never"], var.image_pull_policy)
    error_message = "image_pull_policy must be Always, IfNotPresent or Never."
  }
}

variable "app_version" {
  description = "Version string reported by /version and set as a label. Must be a valid label value."
  type        = string
  default     = "dev"

  validation {
    condition     = can(regex("^[A-Za-z0-9]([-_.A-Za-z0-9]{0,61}[A-Za-z0-9])?$", var.app_version))
    error_message = "app_version must be a valid Kubernetes label value (max 63 characters, alphanumeric, '-', '_' or '.')."
  }
}

variable "replicas" {
  description = "Initial replica count. Terraform ignores later changes to replicas so the HPA (or kubectl scale) can own them."
  type        = number
  default     = 2

  validation {
    condition     = var.replicas >= 1 && var.replicas <= 10 && floor(var.replicas) == var.replicas
    error_message = "replicas must be a whole number between 1 and 10."
  }
}

variable "container_port" {
  description = "Port the application listens on inside the container."
  type        = number
  default     = 8080

  validation {
    condition     = var.container_port >= 1024 && var.container_port <= 65535
    error_message = "container_port must be between 1024 and 65535 (the container runs as non-root)."
  }
}

variable "service_port" {
  description = "Port exposed by the Service."
  type        = number
  default     = 80

  validation {
    condition     = var.service_port >= 1 && var.service_port <= 65535
    error_message = "service_port must be between 1 and 65535."
  }
}

variable "service_type" {
  description = "Service type."
  type        = string
  default     = "ClusterIP"

  validation {
    condition     = contains(["ClusterIP", "NodePort", "LoadBalancer"], var.service_type)
    error_message = "service_type must be ClusterIP, NodePort or LoadBalancer."
  }
}

variable "dns_stub" {
  description = "Set DNS_STUB=true so the app answers /api/dns from a built-in table. For CI and demos without outbound DNS only."
  type        = bool
  default     = false
}

variable "dns_timeout_seconds" {
  description = "Per-lookup timeout passed to the app as DNS_TIMEOUT_SECONDS."
  type        = number
  default     = 2

  validation {
    condition     = var.dns_timeout_seconds > 0 && var.dns_timeout_seconds <= 10
    error_message = "dns_timeout_seconds must be greater than 0 and at most 10."
  }
}

variable "resources" {
  description = "Container resource requests and limits."
  type = object({
    requests = object({ cpu = string, memory = string })
    limits   = object({ cpu = string, memory = string })
  })
  default = {
    requests = { cpu = "50m", memory = "64Mi" }
    limits   = { cpu = "250m", memory = "128Mi" }
  }
}

variable "wait_for_rollout" {
  description = "Make Terraform wait until the Deployment rollout is complete."
  type        = bool
  default     = true
}

variable "enable_hpa" {
  description = "Create a HorizontalPodAutoscaler (autoscaling/v2). It only acts if metrics-server is installed in the cluster."
  type        = bool
  default     = true
}

variable "hpa_min_replicas" {
  description = "HPA minimum replicas."
  type        = number
  default     = 2

  validation {
    condition     = var.hpa_min_replicas >= 1 && var.hpa_min_replicas <= 20
    error_message = "hpa_min_replicas must be between 1 and 20."
  }
}

variable "hpa_max_replicas" {
  description = "HPA maximum replicas."
  type        = number
  default     = 5

  validation {
    condition     = var.hpa_max_replicas >= 1 && var.hpa_max_replicas <= 20
    error_message = "hpa_max_replicas must be between 1 and 20."
  }
}

variable "hpa_cpu_target_percent" {
  description = "Target average CPU utilisation, as a percentage of the CPU request."
  type        = number
  default     = 70

  validation {
    condition     = var.hpa_cpu_target_percent >= 10 && var.hpa_cpu_target_percent <= 95
    error_message = "hpa_cpu_target_percent must be between 10 and 95."
  }
}

variable "enable_pdb" {
  description = "Create a PodDisruptionBudget (max 1 pod unavailable during voluntary disruptions)."
  type        = bool
  default     = true
}

variable "enable_network_policy" {
  description = "Create a default-deny ingress NetworkPolicy plus an allow rule. Only enforced if the CNI supports NetworkPolicy."
  type        = bool
  default     = true
}

variable "ingress_controller_namespace" {
  description = "Namespace of the ingress controller; its pods are allowed to reach the app when the NetworkPolicy is enabled."
  type        = string
  default     = "ingress-nginx"
}

variable "enable_ingress" {
  description = "Create an Ingress for the nginx ingress class."
  type        = bool
  default     = false
}

variable "ingress_host" {
  description = "Host name for the Ingress."
  type        = string
  default     = "lab.localtest.me"
}

variable "ingress_class_name" {
  description = "IngressClass name."
  type        = string
  default     = "nginx"
}

variable "labels" {
  description = "Extra labels applied to every resource."
  type        = map(string)
  default     = {}
}
