output "public_ip" {
  description = "Public IP (EIP) of the k3s node."
  value       = module.compute.public_ip
}

output "kubeconfig_hint" {
  description = "Command to fetch the kubeconfig pointed at the node."
  value       = module.compute.kubeconfig_hint
}
