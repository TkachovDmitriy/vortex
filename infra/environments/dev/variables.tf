variable "region" {
  description = "AWS region."
  type        = string
  default     = "eu-central-1"
}

variable "allowed_cidr" {
  description = "Your public IP as a /32 — the only source allowed to reach SSH, kube-API, and HTTP(S)."
  type        = string
}

variable "instance_type" {
  description = "k3s node size. t3.small (2 GB) app+data; t3.medium (4 GB) full stack."
  type        = string
  default     = "t3.small"
}

variable "public_key_path" {
  description = "Path to the SSH public key used for the node's key pair."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "github_repo" {
  description = "GitHub repo (OWNER/REPO) whose Actions may assume the CI role via OIDC."
  type        = string
  default     = "TkachovDmitriy/vortex"
}
