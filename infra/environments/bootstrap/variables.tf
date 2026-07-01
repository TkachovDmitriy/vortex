variable "region" {
  description = "AWS region for the state bucket."
  type        = string
  default     = "eu-central-1"
}

variable "bucket_name" {
  description = "Globally-unique name for the state bucket, e.g. \"vortex-tofu-state-<account-id>\"."
  type        = string
}
