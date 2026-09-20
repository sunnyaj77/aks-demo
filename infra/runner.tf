# ---------------------------------------------------------------------------
# Self-hosted CI runner VM — see the plan's "CI runner decision" section for
# why this and not a GitHub-hosted runner or ARC-on-cluster. Outbound-only:
# it polls GitHub itself, so nothing needs to reach it, hence the
# deny-all-inbound NSG. Its egress goes through the NAT Gateway defined in
# network.tf, which is what makes its IP static enough to allow-list on the
# AKS API server (see main.tf's authorized_ip_ranges).
# ---------------------------------------------------------------------------
resource "azurerm_network_security_group" "runner" {
  name                = "${var.cluster_name}-runner-nsg"
  location            = data.azurerm_resource_group.this.location
  resource_group_name = data.azurerm_resource_group.this.name

  security_rule {
    name                       = "DenyAllInbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "runner" {
  subnet_id                 = azurerm_subnet.runner.id
  network_security_group_id = azurerm_network_security_group.runner.id
}

resource "azurerm_network_interface" "runner" {
  name                = "${var.cluster_name}-runner-nic"
  location            = data.azurerm_resource_group.this.location
  resource_group_name = data.azurerm_resource_group.this.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.runner.id
    private_ip_address_allocation = "Dynamic"
    # Deliberately no public_ip_address_id here — this NIC has no public
    # IP of its own. Egress is via the subnet's NAT Gateway association
    # instead, which is what keeps the outbound IP static.
  }
}

resource "azurerm_linux_virtual_machine" "runner" {
  name                = "${var.cluster_name}-runner"
  resource_group_name = data.azurerm_resource_group.this.name
  location            = data.azurerm_resource_group.this.location
  size                = var.runner_vm_size
  admin_username      = var.runner_admin_username

  network_interface_ids           = [azurerm_network_interface.runner.id]
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.runner_admin_username
    public_key = var.runner_ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # Installs az CLI / docker CLI / kubectl / helm and registers this VM as
  # a GitHub Actions runner directly (no ARC, no container image — see
  # infra/cloud-init/runner.yaml.tftpl). The registration PAT is used once
  # at boot and never persisted to disk.
  custom_data = base64encode(templatefile("${path.module}/cloud-init/runner.yaml.tftpl", {
    runner_user = var.runner_admin_username
    github_repo = var.github_repo
    github_pat  = var.github_runner_pat
  }))

  identity {
    type = "SystemAssigned"
  }
}
