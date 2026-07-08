# Latest Ubuntu 24.04 LTS (Noble) AMI, owned by Canonical (099720109477).
# Using a data source means we never hardcode a region-specific AMI id.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# SSH key pair — lets you `ssh ubuntu@<ip>` with your private key.
resource "aws_key_pair" "this" {
  key_name   = "${var.name}-key"
  public_key = var.public_key

  tags = merge(var.tags, { Name = "${var.name}-key" })
}

# The k3s node.
resource "aws_instance" "node" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  key_name               = aws_key_pair.this.key_name
  iam_instance_profile   = aws_iam_instance_profile.node.name

  # Bootstrap k3s on first boot (cloud-init runs user_data once). The EIP address
  # is baked in here so the API server cert (--tls-san) is valid for it immediately.
  # user_data only runs at first boot, so changing it must recreate the node —
  # otherwise the new script never runs (default is false).
  user_data = templatefile("${path.module}/user-data.sh.tftpl", {
    public_ip = aws_eip.node.public_ip
  })
  user_data_replace_on_change = true

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
  }

  # IMDSv2 required; hop limit 2 so in-cluster pods (an extra network hop) can reach
  # IMDS to assume the instance role — needed by the ECR-refresh CronJob (ADR-017 §3).
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tags = merge(var.tags, { Name = "${var.name}-node" })
}

# Stable public IP, allocated BEFORE the instance so its address can be baked
# into user_data (--tls-san). Associated to the instance separately below to
# avoid a dependency cycle (instance needs the EIP address → EIP must exist first).
resource "aws_eip" "node" {
  domain = "vpc"

  tags = merge(var.tags, { Name = "${var.name}-eip" })
}

resource "aws_eip_association" "node" {
  instance_id   = aws_instance.node.id
  allocation_id = aws_eip.node.id
}

# ── IAM: let the node pull from ECR without static credentials (ADR-017) ──

# The role's TRUST policy — WHO may assume it: the EC2 service, on the node's behalf.
resource "aws_iam_role" "node" {
  name = "${var.name}-node"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(var.tags, { Name = "${var.name}-node" })
}

# The role's PERMISSIONS — WHAT it may do: read-only pull from ECR (AWS-managed policy).
resource "aws_iam_role_policy_attachment" "ecr_readonly" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# The wrapper that lets an EC2 instance actually wear the role (EC2 can't attach a
# role directly — it references an instance profile, which references the role).
resource "aws_iam_instance_profile" "node" {
  name = "${var.name}-node"
  role = aws_iam_role.node.name

  tags = merge(var.tags, { Name = "${var.name}-node" })
}
