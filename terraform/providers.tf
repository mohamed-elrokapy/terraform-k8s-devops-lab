# Works with any cluster: point kubeconfig_path / kube_context at it.
# The default context targets the local kind cluster on purpose, so a plain `terraform apply`
# can never land on a real cluster by accident.
provider "kubernetes" {
  config_path    = pathexpand(var.kubeconfig_path)
  config_context = var.kube_context
}
