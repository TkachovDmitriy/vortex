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

  # Bootstrap k3s on first boot (cloud-init runs user_data once). The EIP address
  # is baked in here so the API server cert (--tls-san) is valid for it immediately.
  # user_data only runs at first boot, so changing it must recreate the node —
  # otherwise the new script never runs (default is false).
  user_data                   = templatefile("${path.module}/user-data.sh.tftpl", {
    public_ip = aws_eip.node.public_ip
  })
  user_data_replace_on_change = true

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
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
