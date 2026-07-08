variable "repository_names" {
  description = "ECR repository names, one per service (e.g. [\"vortex-gateway\", ...])."
  type        = list(string)
}

variable "keep_last_images" {
  description = "How many tagged images to retain per repo before the lifecycle policy expires older ones."
  type        = number
  default     = 5
}

variable "tags" {
  description = "Tags applied to every repository."
  type        = map(string)
  default     = {}
}
