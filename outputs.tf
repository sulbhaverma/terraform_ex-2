output "vm_ip" {
  value = azurerm_public_ip.public_ip.ip_address
}

output "custom_image_id" {
  value = azurerm_image.custom_image.id
}

output "scale_set_name" {
  value = azurerm_linux_virtual_machine_scale_set.vmss.name
}
