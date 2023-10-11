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
      name = "GatewayAPI-mainnet"
    }
  }

  required_version = ">= 0.14.9"
}

############################################################################
## Variables ###############################################################
locals {
  aws_region    = "us-east-2"
  network_name  = "Monet"
  network_type  = "mainnet"

  vpc_cidr_block      = "10.0.0.0/16"
  subnet_cidr_block_a = "10.0.0.0/20"
  subnet_cidr_block_b = "10.0.16.0/20"
  subnet_cidr_block_c = "10.0.32.0/20"

  server_key_name = "${local.network_name}-${local.network_type}-APIGateway-ssh-key"
  server_user     = "ubuntu"

  inv_file_name = "${local.network_name}-${local.network_type}-APIGateway.inventory"
  vpc_name      = "${local.network_name}-${local.network_type}-APIGateway-VPC"
}

###########################################################################
######################## Basic network resources ##########################
# Set the provider
provider "aws" {
  profile = "default"
  region  = local.aws_region
}

# Create a VPC
resource "aws_vpc" "vpc_pastel_network" {
  cidr_block = local.vpc_cidr_block
  enable_dns_hostnames = true
  enable_dns_support = true

  tags = {
    Name = local.vpc_name
    Role = "VPC"
    Env = local.network_type
  }
}

# Create internet gateway for new VPC
resource "aws_internet_gateway" "psl_internet_gateway" {
  vpc_id = aws_vpc.vpc_pastel_network.id

  tags = {
    Name = format("%s %s - InternetGateway", local.network_name, local.network_type)
    Role = "InternetGateway"
    Env = local.network_type
  }
}

resource "aws_route_table" "pls_internet_route_table" {
  vpc_id = aws_vpc.vpc_pastel_network.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.psl_internet_gateway.id
  }

  tags = {
    Name = format("%s %s - RouteTable", local.network_name, local.network_type)
    Role = "RouteTable"
    Env = local.network_type
  }
}

# Create subnet A
resource "aws_subnet" "pastel_network_subnet_A" {
  vpc_id     = aws_vpc.vpc_pastel_network.id
  cidr_block = local.subnet_cidr_block_a
  availability_zone = "${local.aws_region}a"

  tags = {
    Name = format("%s %s - Subnet A", local.network_name, local.network_type)
    Role = "Subnet"
    Env = local.network_type
  }
}
resource "aws_route_table_association" "psl_route_table_association_A" {
  subnet_id      = aws_subnet.pastel_network_subnet_A.id
  route_table_id = aws_route_table.pls_internet_route_table.id
}

# Create subnet B
resource "aws_subnet" "pastel_network_subnet_B" {
  vpc_id     = aws_vpc.vpc_pastel_network.id
  cidr_block = local.subnet_cidr_block_b
  availability_zone = "${local.aws_region}b"

  tags = {
    Name = format("%s %s - Subnet B", local.network_name, local.network_type)
    Role = "Subnet"
    Env = local.network_type
  }
}
resource "aws_route_table_association" "psl_route_table_association_B" {
  subnet_id      = aws_subnet.pastel_network_subnet_B.id
  route_table_id = aws_route_table.pls_internet_route_table.id
}

# Create subnet C
resource "aws_subnet" "pastel_network_subnet_C" {
  vpc_id     = aws_vpc.vpc_pastel_network.id
  cidr_block = local.subnet_cidr_block_c
  availability_zone = "${local.aws_region}c"

  tags = {
    Name = format("%s %s - Subnet C", local.network_name, local.network_type)
    Role = "Subnet"
    Env = local.network_type
  }
}
resource "aws_route_table_association" "psl_route_table_association_C" {
  subnet_id      = aws_subnet.pastel_network_subnet_C.id
  route_table_id = aws_route_table.pls_internet_route_table.id
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
  source                  = "../modules/openapi"
  region                  = local.aws_region
  network_name            = local.network_name
  network_type            = local.network_type

  vpc_id    = data.aws_vpc.vpc_pastel_network.id
  subnet_id = aws_subnet.pastel_network_subnet_A.id

 server_drive_size       = 200 # default: 100
#  server_instance_type    = default: "t2.large"

  server_type             = "proxy"
  server_count            = 1
  server_ami              = "ami-097a2df4ac947655f"  # ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-2022-0912
  server_key_name         = local.server_key_name

  server_open_ports       = {
    22    = ["0.0.0.0/0"],
    80    = ["0.0.0.0/0"],
    443   = ["0.0.0.0/0"],
    5555  = ["0.0.0.0/0"],  #flowers WEB UI
    5672  = ["0.0.0.0/0"],  #pgadmin
    8080  = ["0.0.0.0/0"]   #API backend
  }
}

############################################################################
## EFS ##################################################################
resource "aws_security_group" "efs_security_group_target" {
  name = "EFS Taget - mainnet"
  description = "EFS Taget - mainnet, to be assigned to EC2"
  vpc_id = data.aws_vpc.vpc_pastel_network.id
}
resource "aws_security_group" "efs_security_group_mount" {
  name = "EFS Mount - mainnet"
  description = "EFS Mount - mainnet, to be assigned to EFS"
  vpc_id = data.aws_vpc.vpc_pastel_network.id
  ingress {
    from_port = 2049
    to_port = 2049
    protocol = "tcp"
    security_groups = [aws_security_group.efs_security_group_target.id]
  }
}

resource "aws_efs_file_system" "efs_storage" {
  # creation_token = 
  performance_mode = "generalPurpose"
  throughput_mode = "bursting"
}

data "aws_vpc" "vpc_pastel_network" {
  tags = {
    Name = local.vpc_name
  }
}

data "aws_subnets" "efs_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.vpc_pastel_network.id]
  }
}

resource "aws_efs_mount_target" "mount_targets" {
  for_each = toset(data.aws_subnets.efs_subnets.ids)
  file_system_id  = aws_efs_file_system.efs_storage.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs_security_group_mount.id]
}

############################################################################
## Master ##################################################################
module "master" {
  source                  = "../modules/openapi"
  region                  = local.aws_region
  network_name            = local.network_name
  network_type            = local.network_type
  
  vpc_id    = data.aws_vpc.vpc_pastel_network.id
  subnet_id = aws_subnet.pastel_network_subnet_A.id

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
    4001  = ["0.0.0.0/0"],   #ipfs
    6379  = formatlist("%s/32", concat(module.proxy.instance_private_ips, module.worker.instance_private_ips))   #redis
  }
}

############################################################################
## Worker ##################################################################
module "worker" {
  source                  = "../modules/openapi"
  region                  = local.aws_region
  network_name            = local.network_name
  network_type            = local.network_type

  vpc_id    = data.aws_vpc.vpc_pastel_network.id
  subnet_id = aws_subnet.pastel_network_subnet_A.id

  server_drive_size       = 200 # default: 100
#  server_instance_type    = default: "t2.large"

  server_type             = "worker"
  server_count            = 1
  server_ami              = "ami-097a2df4ac947655f"  # ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-2022-0912
  server_key_name         = local.server_key_name
  server_efs_sg_id        = aws_security_group.efs_security_group_target.id

  server_open_ports       = {
    22    = ["0.0.0.0/0"],
    4001  = ["0.0.0.0/0"]   #ipfs
  }
}

############################################################################
## IPFS Cluster ############################################################
module "ipfs_peer" {
  source                  = "../modules/openapi"
  region                  = local.aws_region
  network_name            = local.network_name
  network_type            = local.network_type

  vpc_id    = data.aws_vpc.vpc_pastel_network.id
  subnet_id = aws_subnet.pastel_network_subnet_A.id

  server_drive_size       = 700 # default: 100
  server_instance_type    = "m5a.xlarge"

  server_type             = "ipfs_peer"
  server_count            = 3
  server_ami              = "ami-097a2df4ac947655f"  # ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-2022-0912
  server_key_name         = local.server_key_name
  server_efs_sg_id        = aws_security_group.efs_security_group_target.id

  server_open_ports       = {
    22    = ["0.0.0.0/0"],
    4001  = ["0.0.0.0/0"] #formatlist("%s/32", concat(module.proxy.instance_private_ips,module.master.instance_private_ips))   #ipfs
  }
}

########################################################################
## Ansible Inventory ###################################################

resource "local_file" "inventory" {
  content  = templatefile("../openapi-inventory.tftpl", {
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

    ipfs_peers                 = module.ipfs_peer.instance_public_ip,
    ipfs_peers_internal_ips    = module.ipfs_peer.instance_private_ips,
    ipfs_peers_ids             = module.ipfs_peer.node_id,
    ipfs_peers_user            = local.server_user,
    ipfs_peers_priv_key_path   = var.server_private_key_path,
   }
  )
  filename = local.inv_file_name

}

