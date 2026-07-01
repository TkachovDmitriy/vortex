# Remote state in S3 with native locking (use_lockfile — no DynamoDB, ADR-010 §4).
# The bucket must already exist: bootstrap it once with the state-backend module
# (local state), then `tofu init -migrate-state` here (ADR-010 §5).
terraform {
  backend "s3" {
    bucket       = "vortex-tofu-state-CHANGEME" # globally-unique; suffix with your account id
    key          = "dev/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}
