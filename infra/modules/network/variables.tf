variable "name" {
  description = "Name prefix for all network resources (e.g. \"vortex-dev\")."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the single public subnet."
  type        = string
  default     = "10.0.1.0/24"
}

variable "allowed_cidr" {
  description = "Source CIDR allowed to reach SSH, the kube-API, and HTTP(S). Scope to your own IP, e.g. \"203.0.113.4/32\"."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
