variable "region" {
  type = string
  default = "us-east-2"
}
variable "network_name" {
  type = string
}
variable "network_type" {
  type = string
}

variable "server_type" {
  type = string
}
variable "server_count" {
  type = number
}
variable "server_ami" {
  type = string
}
variable "server_instance_type" {
  type = string
  default = "t2.large"
}
variable "server_drive_size" {
  type = number
  default = 100
}
variable "server_name_suffix" {
  type = string
  default = ""
}
variable "server_key_name" {
  type = string
}
variable "server_open_ports" {
  type = map(list(string))
  default = {
    22 = ["0.0.0.0/0"]
  }
}
variable "server_efs_sg_id" {
  type = string
  default = ""
}

variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "iam_instance_profile" {
  type = string
  default = ""
}
