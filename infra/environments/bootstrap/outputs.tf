output "bucket_name" {
  description = "State bucket name — put this in every other root's backend.tf."
  value       = module.state_backend.bucket_name
}
