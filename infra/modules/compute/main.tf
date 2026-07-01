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

  # Bootstrap k3s on first boot (cloud-init runs user_data once).
  user_data = file("${path.module}/user-data.sh")

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
  }

  tags = merge(var.tags, { Name = "${var.name}-node" })
}

# Stable public IP, decoupled from the instance's lifecycle.
resource "aws_eip" "node" {
  instance = aws_instance.node.id
  domain   = "vpc"

  tags = merge(var.tags, { Name = "${var.name}-eip" })
}
