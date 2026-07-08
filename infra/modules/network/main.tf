# Pick the first available AZ in the region for our single public subnet.
data "aws_availability_zones" "available" {
  state = "available"
}

# The VPC — the private network box everything lives in (ADR-010).
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, { Name = "${var.name}-vpc" })
}

# One public subnet. map_public_ip_on_launch = true so the k3s node gets a
# public IP automatically (it's a public subnet by virtue of the IGW route below).
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = merge(var.tags, { Name = "${var.name}-public" })
}

# Internet Gateway — the VPC's door to the public internet.
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name}-igw" })
}

# Route table with a default route to the IGW. This is what makes the subnet
# "public": 0.0.0.0/0 -> igw. The implicit local route (VPC CIDR) is added by AWS.
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(var.tags, { Name = "${var.name}-public-rt" })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Security group — the stateful firewall on the k3s node's ENI.
# Every ingress rule is scoped to var.allowed_cidr (your IP), never 0.0.0.0/0.
resource "aws_security_group" "node" {
  name        = "${var.name}-node"
  description = "vortex k3s node: SSH, kube-API, and HTTP(S) ingress from allowed_cidr only"
  vpc_id      = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name}-node" })
}

# SSH — administer the node.
resource "aws_security_group_rule" "ssh" {
  security_group_id = aws_security_group.node.id
  type              = "ingress"
  description       = "SSH"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [var.allowed_cidr]
}

# Kubernetes API server — talk to the cluster with kubectl/helm from your machine.
resource "aws_security_group_rule" "kube_api" {
  security_group_id = aws_security_group.node.id
  type              = "ingress"
  description       = "Kubernetes API server (k3s)"
  from_port         = 6443
  to_port           = 6443
  protocol          = "tcp"
  cidr_blocks       = [var.allowed_cidr]
}

# HTTP / HTTPS — reach the app's ingress (Gateway API / Traefik) in the browser.
resource "aws_security_group_rule" "http" {
  security_group_id = aws_security_group.node.id
  type              = "ingress"
  description       = "HTTP ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = [var.allowed_cidr]
}

resource "aws_security_group_rule" "https" {
  security_group_id = aws_security_group.node.id
  type              = "ingress"
  description       = "HTTPS ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = [var.allowed_cidr]
}

# Egress — allow all outbound (pull images, k3s installer, apt, etc.).
resource "aws_security_group_rule" "egress_all" {
  security_group_id = aws_security_group.node.id
  type              = "egress"
  description       = "All outbound"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}
