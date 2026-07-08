# NOTE: no backend.tf here on purpose — this root uses LOCAL state, because it
# creates the very bucket that every other root will use as its remote backend
# (the chicken-and-egg from ADR-010 §5). Its local terraform.tfstate is gitignored.
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "vortex"
      ManagedBy = "opentofu"
      Purpose   = "tofu-state-backend"
    }
  }
}
