terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
  required_version = ">= 0.14.9"
}

resource "aws_instance" "openapi_node" {
  ami                     = var.server_ami
  instance_type           = var.server_instance_type
  vpc_security_group_ids  = concat([aws_security_group.nsg[0].id], var.server_efs_sg_id != "" ? [var.server_efs_sg_id] : [])

  key_name                = var.server_key_name
  count                   = var.server_count

  tags = {
    Name = format("%s %s - OpenAPI-%s%02d%s", var.network_name, var.network_type, var.server_type, count.index+1,
      length(var.server_name_suffix)>0?format(" %s", var.server_name_suffix):"" )
    NodeID = format("%s%02d", var.server_type, count.index+1)
    Role = format("OpenAPI-%s", var.server_type)
    Env = var.network_type
  }

  root_block_device {
    volume_size = var.server_drive_size
    volume_type = "gp3"
  }
}

resource "aws_security_group" "nsg" {
  count = var.server_count > 0 ? 1 : 0
  name = "${var.network_name}-${var.network_type}-OpenAPI-${var.server_type}-sg"
}
resource "aws_security_group_rule" "other_inbound" {
  for_each = var.server_count > 0 ? var.server_open_ports: {}

  type              = "ingress"
  security_group_id = aws_security_group.nsg[0].id

  from_port   = each.key
  to_port     = each.key
  protocol    = "tcp"
  cidr_blocks = each.value
}
resource "aws_security_group_rule" "allow_all_outbound" {
  type              = "egress"
  security_group_id = aws_security_group.nsg[0].id
  count = var.server_count > 0 ? 1 : 0

  from_port   = 0
  to_port     = 0
  protocol    = -1
  cidr_blocks = ["0.0.0.0/0"]
}

