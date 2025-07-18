# Resource Group
resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

# Fetch availability zones
data "azurerm_availability_zones" "zones" {
  location = var.location
}

# Fetch secret from Key Vault
data "azurerm_key_vault" "kv" {
  name                = var.key_vault_name
  resource_group_name = var.resource_group_name
}

data "azurerm_key_vault_secret" "password" {
  name         = var.key_vault_secret_name
  key_vault_id = data.azurerm_key_vault.kv.id
}

# Network
resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-demo"
  address_space       = ["10.0.0.0/16"]
  location            = var.location
  resource_group_name = var.resource_group_name
}

resource "azurerm_subnet" "subnet" {
  name                 = "subnet-demo"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_public_ip" "public_ip" {
  name                = "vm-ip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Dynamic"
}

resource "azurerm_network_interface" "nic" {
  name                = "vm-nic"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.public_ip.id
  }
}

# Ubuntu VM
resource "azurerm_linux_virtual_machine" "vm" {
  name                = "vm-apache"
  location            = var.location
  resource_group_name = var.resource_group_name
  size                = "Standard_B1s"
  admin_username      = var.admin_username
  admin_password      = data.azurerm_key_vault_secret.password.value
  network_interface_ids = [azurerm_network_interface.nic.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  disable_password_authentication = false

  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y apache2",
      "echo '<h1>Custom image deployed from Terraform!</h1>' | sudo tee /var/www/html/index.html"
    ]

    connection {
      type     = "ssh"
      user     = var.admin_username
      password = data.azurerm_key_vault_secret.password.value
      host     = azurerm_public_ip.public_ip.ip_address
    }
  }

  depends_on = [azurerm_public_ip.public_ip]
}

# Deprovision the VM
resource "null_resource" "deprovision" {
  provisioner "remote-exec" {
    inline = [
      "sudo waagent -deprovision+user -force && sudo shutdown -h now"
    ]

    connection {
      type     = "ssh"
      user     = var.admin_username
      password = data.azurerm_key_vault_secret.password.value
      host     = azurerm_public_ip.public_ip.ip_address
    }
  }

  depends_on = [azurerm_linux_virtual_machine.vm]
}

# Image creation
resource "azurerm_image" "custom_image" {
  name                = "ubuntu-custom-image"
  location            = var.location
  resource_group_name = var.resource_group_name
  source_virtual_machine_id = azurerm_linux_virtual_machine.vm.id

  depends_on = [null_resource.deprovision]
}

# VM Scale Set using image
resource "azurerm_linux_virtual_machine_scale_set" "vmss" {
  name                = "vmss-demo"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard_B1s"
  instances           = length(data.azurerm_availability_zones.zones.names)
  zones               = data.azurerm_availability_zones.zones.names

  admin_username = var.admin_username
  admin_password = data.azurerm_key_vault_secret.password.value

  source_image_id = azurerm_image.custom_image.id
  upgrade_mode    = "Manual"

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  network_interface {
    name    = "vmss-nic"
    primary = true

    ip_configuration {
      name      = "vmss-ipconfig"
      subnet_id = azurerm_subnet.subnet.id
    }
  }

  depends_on = [azurerm_image.custom_image]
}
