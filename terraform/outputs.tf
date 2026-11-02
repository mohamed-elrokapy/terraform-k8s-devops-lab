output "namespace" {
  description = "Namespace the application runs in."
  value       = module.app.namespace
}

output "deployment_name" {
  description = "Name of the Deployment."
  value       = module.app.deployment_name
}

output "service_name" {
  description = "Name of the Service."
  value       = module.app.service_name
}

output "port_forward_command" {
  description = "Command that exposes the Service on http://localhost:8080."
  value       = "kubectl --context ${coalesce(var.kube_context, "<current-context>")} -n ${module.app.namespace} port-forward svc/${module.app.service_name} 8080:${module.app.service_port}"
}

output "ingress_host" {
  description = "Host name served by the Ingress, or null when the Ingress is disabled."
  value       = module.app.ingress_host
}
