locals {
  selector_labels = {
    "app.kubernetes.io/name"     = var.name
    "app.kubernetes.io/instance" = var.name
  }

  labels = merge(
    var.labels,
    local.selector_labels,
    {
      "app.kubernetes.io/version"    = var.app_version
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "terraform-k8s-devops-lab"
    },
  )

  # Environment for the app. ConfigMap values must be strings.
  config = {
    APP_VERSION         = var.app_version
    DNS_STUB            = tostring(var.dns_stub)
    DNS_TIMEOUT_SECONDS = tostring(var.dns_timeout_seconds)
  }
}

resource "kubernetes_namespace_v1" "this" {
  metadata {
    name = var.namespace
    labels = merge(local.labels, {
      "pod-security.kubernetes.io/enforce"         = var.pod_security_level
      "pod-security.kubernetes.io/enforce-version" = "latest"
    })
  }
}

resource "kubernetes_config_map_v1" "this" {
  metadata {
    name      = var.name
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }

  data = local.config
}

resource "kubernetes_deployment_v1" "this" {
  metadata {
    name      = var.name
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }

  wait_for_rollout = var.wait_for_rollout

  timeouts {
    create = "3m"
    update = "3m"
    delete = "2m"
  }

  spec {
    replicas               = tostring(var.replicas)
    revision_history_limit = 3

    selector {
      match_labels = local.selector_labels
    }

    strategy {
      type = "RollingUpdate"
      rolling_update {
        max_surge       = "1"
        max_unavailable = "0"
      }
    }

    template {
      metadata {
        labels = local.labels
        annotations = {
          # Changing the ConfigMap changes this hash, which rolls the pods (env vars are read at start).
          "checksum/config"      = sha256(jsonencode(local.config))
          "prometheus.io/scrape" = "true"
          "prometheus.io/path"   = "/metrics"
          "prometheus.io/port"   = tostring(var.container_port)
        }
      }

      spec {
        automount_service_account_token  = false
        enable_service_links             = false
        termination_grace_period_seconds = 30

        security_context {
          run_as_non_root = true
          run_as_user     = "10001"
          run_as_group    = "10001"
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name              = "app"
          image             = var.image
          image_pull_policy = var.image_pull_policy

          port {
            name           = "http"
            container_port = var.container_port
            protocol       = "TCP"
          }

          env_from {
            config_map_ref {
              name = kubernetes_config_map_v1.this.metadata[0].name
            }
          }

          resources {
            requests = var.resources.requests
            limits   = var.resources.limits
          }

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            run_as_non_root            = true
            capabilities {
              drop = ["ALL"]
            }
            seccomp_profile {
              type = "RuntimeDefault"
            }
          }

          # Gives the app up to 30s (15 x 2s) to start before liveness takes over.
          startup_probe {
            http_get {
              path = "/healthz"
              port = "http"
            }
            period_seconds    = 2
            failure_threshold = 15
            timeout_seconds   = 2
          }

          liveness_probe {
            http_get {
              path = "/healthz"
              port = "http"
            }
            period_seconds    = 10
            failure_threshold = 3
            timeout_seconds   = 2
          }

          readiness_probe {
            http_get {
              path = "/readyz"
              port = "http"
            }
            period_seconds    = 5
            failure_threshold = 2
            timeout_seconds   = 2
          }

          # The root filesystem is read-only; /tmp is the only writable path.
          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }
        }

        volume {
          name = "tmp"
          empty_dir {
            size_limit = "16Mi"
          }
        }

        topology_spread_constraint {
          max_skew           = 1
          topology_key       = "kubernetes.io/hostname"
          when_unsatisfiable = "ScheduleAnyway"
          label_selector {
            match_labels = local.selector_labels
          }
        }
      }
    }
  }

  lifecycle {
    # The HPA (or kubectl scale) owns the replica count after the first apply.
    ignore_changes = [spec[0].replicas]
  }
}

resource "kubernetes_service_v1" "this" {
  metadata {
    name      = var.name
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }

  spec {
    type     = var.service_type
    selector = local.selector_labels

    port {
      name        = "http"
      port        = var.service_port
      target_port = "http"
      protocol    = "TCP"
    }
  }
}

resource "kubernetes_horizontal_pod_autoscaler_v2" "this" {
  count = var.enable_hpa ? 1 : 0

  metadata {
    name      = var.name
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }

  spec {
    min_replicas = var.hpa_min_replicas
    max_replicas = var.hpa_max_replicas

    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment_v1.this.metadata[0].name
    }

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = var.hpa_cpu_target_percent
        }
      }
    }
  }

  lifecycle {
    precondition {
      condition     = var.hpa_min_replicas <= var.hpa_max_replicas
      error_message = "hpa_min_replicas must be less than or equal to hpa_max_replicas."
    }
  }
}

resource "kubernetes_pod_disruption_budget_v1" "this" {
  count = var.enable_pdb ? 1 : 0

  metadata {
    name      = var.name
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }

  spec {
    # max_unavailable (not min_available) so a single-replica install can still be drained.
    max_unavailable = "1"
    selector {
      match_labels = local.selector_labels
    }
  }
}

resource "kubernetes_network_policy_v1" "default_deny_ingress" {
  count = var.enable_network_policy ? 1 : 0

  metadata {
    name      = "default-deny-ingress"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }

  spec {
    # An empty selector matches every pod in the namespace; no ingress rules means nothing is allowed in.
    pod_selector {}
    policy_types = ["Ingress"]
  }
}

resource "kubernetes_network_policy_v1" "allow_ingress" {
  count = var.enable_network_policy ? 1 : 0

  metadata {
    name      = "${var.name}-allow-ingress"
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }

  spec {
    pod_selector {
      match_labels = local.selector_labels
    }
    policy_types = ["Ingress"]

    ingress {
      ports {
        port     = "http"
        protocol = "TCP"
      }

      # The ingress controller namespace.
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = var.ingress_controller_namespace
          }
        }
      }

      # Other pods in this namespace.
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = kubernetes_namespace_v1.this.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_ingress_v1" "this" {
  count = var.enable_ingress ? 1 : 0

  # Do not block on a load balancer address; a kind cluster never assigns one.
  wait_for_load_balancer = false

  metadata {
    name      = var.name
    namespace = kubernetes_namespace_v1.this.metadata[0].name
    labels    = local.labels
  }

  spec {
    ingress_class_name = var.ingress_class_name

    rule {
      host = var.ingress_host
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service_v1.this.metadata[0].name
              port {
                number = var.service_port
              }
            }
          }
        }
      }
    }
  }
}
