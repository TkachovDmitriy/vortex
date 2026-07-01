locals {
  name = "vortex-dev"
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
  public_key        = file(var.public_key_path)
}
