variable "name" {
  description = "Name prefix for the CI role (e.g. vortex-dev)."
  type        = string
}

variable "github_repo" {
  description = "GitHub repo allowed to assume the role, as OWNER/REPO."
  type        = string
}

variable "branch" {
  description = "Branch whose workflow runs may assume the role (push events)."
  type        = string
  default     = "develop"
}

variable "ecr_repository_arns" {
  description = "ECR repository ARNs the CI role may push to (least-privilege)."
  type        = list(string)
}

variable "tags" {
  description = "Tags applied to the IAM role."
  type        = map(string)
  default     = {}
}
