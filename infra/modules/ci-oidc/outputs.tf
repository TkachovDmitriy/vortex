output "role_arn" {
  description = "ARN of the CI role — set as role-to-assume in the GitHub workflow."
  value       = aws_iam_role.ci.arn
}
