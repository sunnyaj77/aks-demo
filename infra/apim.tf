# ---------------------------------------------------------------------------
# APIM's subnet needs specific inbound/outbound rules or the platform
# refuses (or silently degrades) the VNet integration — these mirror
# Microsoft's documented "virtual network configuration reference" rule
# set as of this plan being written. Azure has revised this list before;
# double-check it against the current docs before `terraform apply` if
# this sits unapplied for a while.
# ---------------------------------------------------------------------------
resource "azurerm_network_security_group" "apim" {
  name                = "${var.cluster_name}-apim-nsg"
  location            = data.azurerm_resource_group.this.location
  resource_group_name = data.azurerm_resource_group.this.name

  security_rule {
    name                       = "AllowClientToAPIMGateway"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["443", "80"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "AllowAzureManagementToAPIM"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3443"
    source_address_prefix      = "ApiManagement"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "AllowAzureLoadBalancerToAPIM"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "AllowAPIMToStorage"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "Storage"
  }

  security_rule {
    name                       = "AllowAPIMToSql"
    priority                   = 110
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "1433"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "Sql"
  }

  security_rule {
    name                       = "AllowAPIMToKeyVault"
    priority                   = 120
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "AzureKeyVault"
  }

  security_rule {
    name                       = "AllowAPIMToAAD"
    priority                   = 130
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "AzureActiveDirectory"
  }

  security_rule {
    name                       = "AllowAPIMToMonitor"
    priority                   = 140
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["443", "1886"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "AzureMonitor"
  }

  # Cache-sync between APIM units (rate-limit/quota state) — harmless with
  # a single Developer-tier unit, but cheap to have in place if this ever
  # scales to more than one unit.
  security_rule {
    name                       = "AllowAPIMUnitSync"
    priority                   = 150
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["6381", "6382", "6383"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "AllowAPIMToInternet"
    priority                   = 160
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = "Internet"
  }
}

resource "azurerm_subnet_network_security_group_association" "apim" {
  subnet_id                 = azurerm_subnet.apim.id
  network_security_group_id = azurerm_network_security_group.apim.id
}

# ---------------------------------------------------------------------------
# APIM itself — Developer SKU (confirmed), Internal VNet mode, no public
# endpoint at all. Provisioning this is slow (commonly 30-45 minutes) —
# kick it off first if applying incrementally.
# ---------------------------------------------------------------------------
resource "azurerm_api_management" "this" {
  name                = "apim-aksdemo-${random_string.suffix.result}"
  location            = data.azurerm_resource_group.this.location
  resource_group_name = data.azurerm_resource_group.this.name
  publisher_name      = var.apim_publisher_name
  publisher_email     = var.apim_publisher_email

  sku_name             = "Developer_1"
  virtual_network_type = "Internal"

  virtual_network_configuration {
    subnet_id = azurerm_subnet.apim.id
  }

  identity {
    type = "SystemAssigned"
  }

  depends_on = [azurerm_subnet_network_security_group_association.apim]
}

# Not the Kubernetes-specific Workload Identity chain the pods use — APIM
# isn't a Kubernetes workload, so a standard Azure system-assigned identity
# + RBAC is the equivalent here.
resource "azurerm_role_assignment" "apim_kv_secrets_user" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_api_management.this.identity[0].principal_id
}

# api.aks-demo.internal -> APIM's private IP. This is the DNS name the
# frontend's APIM_GATEWAY_URL should be set to (see
# charts/nextjs-app/values.yaml's apim.gatewayUrl) once this applies.
resource "azurerm_private_dns_a_record" "apim" {
  name                = "api"
  zone_name           = azurerm_private_dns_zone.internal.name
  resource_group_name = data.azurerm_resource_group.this.name
  ttl                 = 300
  records             = [azurerm_api_management.this.private_ip_addresses[0]]
}
