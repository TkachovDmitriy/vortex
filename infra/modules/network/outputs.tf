output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "subnet_id" {
  description = "ID of the public subnet the k3s node lands in."
  value       = aws_subnet.public.id
}

output "security_group_id" {
  description = "ID of the k3s node security group (consumed by the compute module)."
  value       = aws_security_group.node.id
}
