variable "bucket_name" {
  description = "Globally-unique S3 bucket name for OpenTofu remote state (e.g. \"vortex-tofu-state-<account-id>\")."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
