terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.0.0"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "gzeru_rg" {
  name     = "gzeru_rg"
  location = "West Europe"
  tags = {
    enviroment = "dev"
  }
}

resource "azurerm_virtual_network" "gz-vn" {
  name                = "gz-network"
  resource_group_name = azurerm_resource_group.gzeru_rg.name
  location            = azurerm_resource_group.gzeru_rg.location
  address_space       = ["10.123.0.0/16"]

  tags = {
    enviroment = "dev"
  }
}

resource "azurerm_subnet" "gz-subnet" {
  name                 = "gz-subnet"
  resource_group_name  = azurerm_resource_group.gzeru_rg.name
  virtual_network_name = azurerm_virtual_network.gz-vn.name
  address_prefixes     = ["10.123.1.0/24"]
}

resource "azurerm_network_security_group" "gz-sg" {
  name                = "gz-sg"
  location            = azurerm_resource_group.gzeru_rg.location
  resource_group_name = azurerm_resource_group.gzeru_rg.name

  tags = {
    enviroment = "dev"
  }
}
resource "azurerm_network_security_rule" "gz-dev-rule" {
  name                        = "gz-dev-rule"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  network_security_group_name = azurerm_network_security_group.gz-sg.name
  resource_group_name         = azurerm_resource_group.gzeru_rg.name

}

resource "azurerm_subnet_network_security_group_association" "gz-sga" {
  subnet_id                 = azurerm_subnet.gz-subnet.id
  network_security_group_id = azurerm_network_security_group.gz-sg.id
}

resource "azurerm_public_ip" "gz-ip" {
  name                    = "gz-pip"
  location                = azurerm_resource_group.gzeru_rg.location
  resource_group_name     = azurerm_resource_group.gzeru_rg.name
  allocation_method       = "Dynamic"
  idle_timeout_in_minutes = 30

  tags = {
    environment = "Dev"
  }
}

resource "azurerm_network_interface" "gz-nic" {
  name                = "gz-nic"
  location            = azurerm_resource_group.gzeru_rg.location
  resource_group_name = azurerm_resource_group.gzeru_rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.gz-subnet.id
    private_ip_address_allocation = "Dynamic"
    private_ip_address            = "10.0.2.5"
    public_ip_address_id          = azurerm_public_ip.gz-ip.id
  }

  tags = {
    enviroment = "Dev"
  }
}

# create ssh key pair locally then create linux vm
resource "azurerm_linux_virtual_machine" "gz-linux-vm-1" {
  name                = "gzlinux01"
  resource_group_name = azurerm_resource_group.gzeru_rg.name
  location            = azurerm_resource_group.gzeru_rg.location
  size                = "Standard_F2"
  admin_username      = "adminuser"
  network_interface_ids = [
    azurerm_network_interface.gz-nic.id,
  ]

  #customdata

  custom_data = filebase64("customdata.tpl")

  admin_ssh_key {
    username   = "adminuser"
    public_key = file("~/.ssh/id_azure.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }
  #script call from .tpl files

  provisioner "local-exec" {
    command = templatefile("${var.host_os}-ssh-script.tpl", {
      hostname     = self.public_ip_address,
      user         = "adminuser",
      identityfile = "~/.ssh/id-azure"
    })
    interpreter = ["Powershell", "-Command"]
  }

  tags = {
    enviroment = "Dev"
  }
}

data "azurerm_public_ip" "gz-ip-data" {
  name                = azurerm_public_ip.gz-ip.name
  resource_group_name = azurerm_resource_group.gzeru_rg.name
}

output "public_ip_address" {
  value = "${azurerm_linux_virtual_machine.gz-linux-vm-1.name}: ${data.azurerm_public_ip.gz-ip-data.ip_address}"
}