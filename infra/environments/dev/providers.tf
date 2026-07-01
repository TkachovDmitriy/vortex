# Credentials come from the local AWS profile / env vars, never hardcoded (ADR-010 §8).
# default_tags stamps every resource in this root, so modules don't each pass tags.
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "vortex"
      Environment = "dev"
      ManagedBy   = "opentofu"
    }
  }
}
