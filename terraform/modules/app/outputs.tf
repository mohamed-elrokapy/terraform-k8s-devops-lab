output "namespace" {
  description = "Namespace the application runs in."
  value       = kubernetes_namespace_v1.this.metadata[0].name
}

output "deployment_name" {
  description = "Name of the Deployment."
  value       = kubernetes_deployment_v1.this.metadata[0].name
}

output "service_name" {
  description = "Name of the Service."
  value       = kubernetes_service_v1.this.metadata[0].name
}

output "service_port" {
  description = "Port exposed by the Service."
  value       = var.service_port
}

output "ingress_host" {
  description = "Ingress host name, or null when the Ingress is disabled."
  value       = var.enable_ingress ? var.ingress_host : null
}
