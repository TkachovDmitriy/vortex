# Creates the S3 bucket that holds remote state for all other roots.
# Run once: `tofu init && tofu apply`, then copy bucket_name into each backend.tf.
module "state_backend" {
  source      = "../../modules/state-backend"
  bucket_name = var.bucket_name
}
