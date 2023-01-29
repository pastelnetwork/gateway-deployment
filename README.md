# openapi-deployment

## Quick start

### 1. Run terraform to create infrastructure

```shell
cd terraform
```

#### Create variables pointing to the SSH keys (keys must exist)
Create file `override.tf`
```
variable "server_public_key_path" {
  type = string
  default = "<Path to public key>"
}
variable "server_private_key_path" {
  type = string
  default = "<Path to private key>"
}
```

#### Edit "cloud terraform" and "AWS" settings in `main.tf`
```
  cloud {
    organization = CHANGE_ME
    workspaces {
      name = CHANGE_ME
    }
  }
...
locals {
  region = "us-east-2"
  network = "MySetup"
  type    = "testnet"
... 
```

#### Run terraform
```shell
terraform apply
```

#### Copy created `*.inventory` file to ansible directory
```shell
cp MySetup-testnet-OpenAPI.inventory ../ansible
```

### 2. Run ansible to setup required software and configure it

```
cd ansible
ansible-playbook -i MySetup-testnet-OpenAPI.inventory hosted_infra.yml
```
