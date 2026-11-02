module "app" {
  source = "./modules/app"

  namespace         = var.namespace
  image             = var.image
  image_pull_policy = var.image_pull_policy
  app_version       = var.app_version
  replicas          = var.replicas
  dns_stub          = var.dns_stub
  wait_for_rollout  = var.wait_for_rollout

  enable_hpa       = var.enable_hpa
  hpa_min_replicas = var.hpa_min_replicas
  hpa_max_replicas = var.hpa_max_replicas

  enable_pdb                   = var.enable_pdb
  enable_network_policy        = var.enable_network_policy
  ingress_controller_namespace = var.ingress_controller_namespace

  enable_ingress = var.enable_ingress
  ingress_host   = var.ingress_host
}
