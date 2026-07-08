# Remote state in S3 with native locking (use_lockfile — no DynamoDB, ADR-010 §4).
# The bucket must already exist (created by environments/bootstrap, ADR-010 §5).
#
# `bucket` is intentionally NOT here — it embeds the AWS account id, which we keep
# out of git. It's a PARTIAL backend config: pass the bucket at init time via
#   tofu init -backend-config=backend.hcl
# (backend.hcl is gitignored; copy backend.hcl.example to create it.)
terraform {
  backend "s3" {
    key          = "dev/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}
