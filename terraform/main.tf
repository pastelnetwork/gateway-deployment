terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
  cloud {
    organization = "PastelNetwork"
    workspaces {
      name = "OpenAPI-testnet"
    }
  }

  required_version = ">= 0.14.9"
}

provider "aws" {
  profile = "default"
  region  = local.region
}

############################################################################
## Variables ###############################################################
locals {
  region = "us-east-2"
  network = "Cezanne"
  type    = "testnet"

  server_key_name         = "${local.network}-${local.type}-OpenAPI-ssh-key"
  server_user             = "ubuntu"

  inv_file_name = "${local.network}-${local.type}-OpenAPI.inventory"
}

############################################################################
## Keys ####################################################################
variable "server_public_key_path" {
  type = string
}
variable "server_private_key_path" {
  type = string
}

resource "aws_key_pair" "ssh-key" {
  key_name   = local.server_key_name
  public_key = file(var.server_public_key_path)
}

######################################################################################################################################################
## Hosts infrastructure ##############################################################################################################################
######################################################################################################################################################

############################################################################
## Proxy ###################################################################
module "proxy" {
  source                  = "./modules/openapi"
  region                  = local.region
  network_name            = local.network
  network_type            = local.type

 server_drive_size       = 200 # default: 100
#  server_instance_type    = default: "t2.large"

  server_type             = "proxy"
  server_count            = 1
  server_ami              = "ami-097a2df4ac947655f"  # ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-2022-0912
  server_key_name         = local.server_key_name

  server_open_ports       = {
    22    = ["0.0.0.0/0"],
    80    = ["0.0.0.0/0"],
    403   = ["0.0.0.0/0"],
    4001  = ["0.0.0.0/0"],  #ipfs
    5555  = ["0.0.0.0/0"],  #flowers WEB UI
    5672  = ["0.0.0.0/0"],  #pgadmin
    8080  = ["0.0.0.0/0"]   #API backend
  }
}

############################################################################
## EFS ##################################################################
resource "aws_security_group" "efs_security_group_target" {
  name = "EFS Target - testnet"
}
resource "aws_security_group" "efs_security_group_mount" {
  name = "EFS Mount - testnet"
  ingress {
    from_port = 2049
    to_port = 2049
    protocol = "tcp"
    security_groups = [aws_security_group.efs_security_group_target.id]
  }
}

resource "aws_efs_file_system" "efs_storage" {
  creation_token = "EFS-Storage"
  performance_mode = "generalPurpose"
  throughput_mode = "bursting"
}

data "aws_vpc" "vpc_pastel_network" {
  tags = {
    Name = "Pastel-Network"
  }
}

data "aws_subnet_ids" "efs_subnets" {
  vpc_id = data.aws_vpc.vpc_pastel_network.id
}

resource "aws_efs_mount_target" "mount_targets" {
  for_each = toset(data.aws_subnet_ids.efs_subnets.ids)
  file_system_id  = aws_efs_file_system.efs_storage.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs_security_group_mount.id]
}

############################################################################
## Master ##################################################################
module "master" {
  source                  = "./modules/openapi"
  region                  = local.region
  network_name            = local.network
  network_type            = local.type

 server_drive_size       = 200 # default: 100
#  server_instance_type    = default: "t2.large"

  server_type             = "master"
  server_count            = 1
  server_ami              = "ami-097a2df4ac947655f"  # ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-2022-0912
  server_key_name         = local.server_key_name
  server_efs_sg_id        = aws_security_group.efs_security_group_target.id

  server_open_ports       = {
    22    = ["0.0.0.0/0"],
    8090  = formatlist("%s/32", module.proxy.instance_private_ips),   #backend
    4001  = formatlist("%s/32", concat(module.proxy.instance_private_ips, module.worker.instance_private_ips)),   #ipfs
    6379  = formatlist("%s/32", concat(module.proxy.instance_private_ips, module.worker.instance_private_ips))   #redis
  }
}

############################################################################
## Worker ##################################################################
module "worker" {
  source                  = "./modules/openapi"
  region                  = local.region
  network_name            = local.network
  network_type            = local.type

 server_drive_size       = 200 # default: 100
#  server_instance_type    = default: "t2.large"

  server_type             = "worker"
  server_count            = 1
  server_ami              = "ami-097a2df4ac947655f"  # ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-2022-0912
  server_key_name         = local.server_key_name
  server_efs_sg_id        = aws_security_group.efs_security_group_target.id

  server_open_ports       = {
    22    = ["0.0.0.0/0"],
    4001  = formatlist("%s/32", concat(module.proxy.instance_private_ips,module.master.instance_private_ips))   #ipfs
  }
}

########################################################################
## Ansible Inventory ###################################################

resource "local_file" "inventory" {
  content  = templatefile("./openapi-inventory.tftpl", {
    proxys                = module.proxy.instance_public_ip,
    proxy_internal_ips    = module.proxy.instance_private_ips,
    proxys_ids            = module.proxy.node_id,
    proxys_user           = local.server_user,
    proxys_priv_key_path  = var.server_private_key_path,

    masters                = module.master.instance_public_ip,
    master_internal_ips    = module.master.instance_private_ips,
    masters_ids            = module.master.node_id,
    masters_user           = local.server_user,
    masters_priv_key_path  = var.server_private_key_path,

    workers                 = module.worker.instance_public_ip,
    workers_internal_ips    = module.worker.instance_private_ips,
    workers_ids             = module.worker.node_id,
    workers_user            = local.server_user,
    workers_priv_key_path   = var.server_private_key_path,
   }
  )
  filename = local.inv_file_name

}

