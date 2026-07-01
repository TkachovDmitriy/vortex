variable "name" {
  description = "Name prefix for compute resources (e.g. \"vortex-dev\")."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type. t3.small (2 GB) for app+data; t3.medium (4 GB) for full stack incl. metrics."
  type        = string
  default     = "t3.small"
}

variable "subnet_id" {
  description = "Public subnet the node lands in (from the network module)."
  type        = string
}

variable "security_group_id" {
  description = "Security group attached to the node (from the network module)."
  type        = string
}

variable "public_key" {
  description = "SSH public key material for the node's key pair (contents of your id_ed25519.pub)."
  type        = string
}

variable "root_volume_size" {
  description = "Root EBS volume size in GB. Free tier allows 30 GB gp3."
  type        = number
  default     = 20
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
