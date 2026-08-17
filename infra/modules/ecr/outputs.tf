output "repository_urls" {
  description = "Map of repo name → full repository URL (registry host + repo path)."
  value       = { for name, repo in aws_ecr_repository.this : name => repo.repository_url }
}

output "registry_url" {
  description = "ECR registry host (<account>.dkr.ecr.<region>.amazonaws.com) — for Helm global.imageRegistry and docker login."
  value       = split("/", values(aws_ecr_repository.this)[0].repository_url)[0]
}

output "repository_arns" {
  description = "Per-service ECR repository ARNs — for scoping the CI push IAM policy."
  value       = [for repo in aws_ecr_repository.this : repo.arn]
}
