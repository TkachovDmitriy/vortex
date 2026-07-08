output "instance_id" {
  description = "EC2 instance id of the k3s node."
  value       = aws_instance.node.id
}

output "public_ip" {
  description = "Stable public IP (EIP) of the node."
  value       = aws_eip.node.public_ip
}

output "kubeconfig_hint" {
  description = "How to fetch the kubeconfig and point it at the node."
  value       = "ssh ubuntu@${aws_eip.node.public_ip} 'sudo sed \"s/127.0.0.1/${aws_eip.node.public_ip}/\" /etc/rancher/k3s/k3s.yaml' > vortex-dev.kubeconfig"
}
