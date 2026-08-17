locals {
  name = "vortex-dev"

  services = ["gateway", "orders", "inventory", "notifications", "analytics"]
}

# Container registry: one private ECR repo per service (ADR-017).
module "ecr" {
  source           = "../../modules/ecr"
  repository_names = [for svc in local.services : "vortex-${svc}"]
}

# Keyless CI → ECR push via GitHub Actions OIDC (no static keys, ADR-021).
module "ci_oidc" {
  source              = "../../modules/ci-oidc"
  name                = local.name
  github_repo         = var.github_repo
  ecr_repository_arns = module.ecr.repository_arns
}

# Network layer: VPC, subnet, IGW, route table, security group (cheap/stable).
module "network" {
  source       = "../../modules/network"
  name         = local.name
  allowed_cidr = var.allowed_cidr
}

# Compute layer: the ephemeral k3s node (paid). Consumes the network outputs.
module "compute" {
  source            = "../../modules/compute"
  name              = local.name
  instance_type     = var.instance_type
  subnet_id         = module.network.subnet_id
  security_group_id = module.network.security_group_id
  public_key        = file(pathexpand(var.public_key_path))
}
