variable "location" {
  default = "eastus"
}

variable "resource_group_name" {
  default = "rg-demo-vmss"
}

variable "key_vault_name" {
  default = "kv-demo-vmss"
}

variable "key_vault_secret_name" {
  default = "vmAdminPassword"
}

variable "admin_username" {
  default = "azureuser"
}
