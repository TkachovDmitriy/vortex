output "public_ip" {
  description = "Public IP (EIP) of the k3s node."
  value       = module.compute.public_ip
}

output "kubeconfig_hint" {
  description = "Command to fetch the kubeconfig pointed at the node."
  value       = module.compute.kubeconfig_hint
}

output "ecr_registry_url" {
  description = "ECR registry host — for `docker login` and Helm global.imageRegistry."
  value       = module.ecr.registry_url
}

output "ecr_repository_urls" {
  description = "Per-service ECR repository URLs (push targets)."
  value       = module.ecr.repository_urls
}

output "ci_role_arn" {
  description = "CI role ARN — set as role-to-assume in the GitHub Actions workflow."
  value       = module.ci_oidc.role_arn
}
