#!/usr/bin/env bash
# Runs once on first boot via cloud-init. Installs a single-node k3s cluster.
set -euo pipefail

# --write-kubeconfig-mode 644 so the kubeconfig is readable without sudo.
# --tls-san adds the public IP to the API server cert, so kubectl from your
# laptop (pointing at the EIP) passes TLS verification.
PUBLIC_IP="$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)"

curl -sfL https://get.k3s.io | sh -s - \
  --write-kubeconfig-mode 644 \
  --tls-san "${PUBLIC_IP}"

# k3s is up. Fetch the kubeconfig from /etc/rancher/k3s/k3s.yaml and replace
# 127.0.0.1 with the public IP to use it from outside the box.
