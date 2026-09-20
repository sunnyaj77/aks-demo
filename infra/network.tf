# ---------------------------------------------------------------------------
# The VNet everything else in this plan lives inside. Nothing here was
# needed for the original single-service demo (AKS defaulted to its own
# auto-managed kubenet VNet) — it's new because Postgres/Redis/Storage/APIM
# all need a real, addressable network to attach to privately.
# ---------------------------------------------------------------------------
resource "azurerm_virtual_network" "this" {
  name                = "${var.cluster_name}-vnet"
  address_space       = [var.vnet_address_space]
  location            = data.azurerm_resource_group.this.location
  resource_group_name = data.azurerm_resource_group.this.name
}

resource "azurerm_subnet" "aks" {
  name                 = "snet-aks"
  resource_group_name  = data.azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.aks_subnet_cidr]
}

resource "azurerm_subnet" "runner" {
  name                 = "snet-runner"
  resource_group_name  = data.azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.runner_subnet_cidr]
}

# Shared by Key Vault, Storage, and Redis's Private Endpoints — they're all
# "point a private NIC at a Microsoft-managed PaaS service" the same way, so
# one subnet for all three keeps the network layout simple.
resource "azurerm_subnet" "private_endpoints" {
  name                 = "snet-private-endpoints"
  resource_group_name  = data.azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.pe_subnet_cidr]

  # Required for a subnet that's going to host Private Endpoints — Azure
  # blocks PE creation in a subnet where these policies are still enabled.
  private_endpoint_network_policies = "Disabled"
}

# Postgres Flexible Server's "VNet-integrated (private access)" mode is a
# genuine network placement, not a Private Endpoint — Azure requires this
# subnet be delegated to the Postgres service and used by nothing else.
resource "azurerm_subnet" "postgres" {
  name                 = "snet-postgres"
  resource_group_name  = data.azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.postgres_subnet_cidr]

  delegation {
    name = "postgres-delegation"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# APIM's VNet integration also can't share a subnet with anything else —
# same "dedicated subnet" requirement as Postgres, different mechanism.
resource "azurerm_subnet" "apim" {
  name                 = "snet-apim"
  resource_group_name  = data.azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [var.apim_subnet_cidr]
}

# ---------------------------------------------------------------------------
# Deterministic egress IP for the runner subnet. The AKS API server stays
# public + Authorized-IP-Ranges (confirmed decision) — that only works if
# the runner VM's outbound IP is static and known ahead of time, which a
# VM's default outbound access is NOT (it's a shared, unpredictable Azure
# IP). A NAT Gateway with its own Standard Public IP fixes that: every
# packet leaving snet-runner exits through this one, always-the-same IP.
# ---------------------------------------------------------------------------
resource "azurerm_public_ip" "runner_nat" {
  name                = "${var.cluster_name}-runner-nat-pip"
  location            = data.azurerm_resource_group.this.location
  resource_group_name = data.azurerm_resource_group.this.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_nat_gateway" "runner" {
  name                = "${var.cluster_name}-runner-natgw"
  location            = data.azurerm_resource_group.this.location
  resource_group_name = data.azurerm_resource_group.this.name
  sku_name            = "Standard"
}

resource "azurerm_nat_gateway_public_ip_association" "runner" {
  nat_gateway_id       = azurerm_nat_gateway.runner.id
  public_ip_address_id = azurerm_public_ip.runner_nat.id
}

resource "azurerm_subnet_nat_gateway_association" "runner" {
  subnet_id      = azurerm_subnet.runner.id
  nat_gateway_id = azurerm_nat_gateway.runner.id
}

# ---------------------------------------------------------------------------
# Private DNS zone for the app's own hostnames (app.aks-demo.internal,
# api.aks-demo.internal) — separate from the Microsoft-managed
# privatelink.*.azure.com zones each PaaS service gets in keyvault.tf /
# postgres.tf / redis.tf / storage.tf, which resolve *their* names, not
# yours. APIM's A record is added in apim.tf, once APIM's private IP
# exists. app.aks-demo.internal's A record is NOT created here — it points
# at the internal LB's IP, which only exists after ingress-nginx is
# installed by Helm (a later step), so that record is added by hand /
# a follow-up kubectl+az step once that IP is known.
# ---------------------------------------------------------------------------
resource "azurerm_private_dns_zone" "internal" {
  name                = "aks-demo.internal"
  resource_group_name = data.azurerm_resource_group.this.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "internal" {
  name                  = "${var.cluster_name}-internal-link"
  resource_group_name  = data.azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.internal.name
  virtual_network_id    = azurerm_virtual_network.this.id
}
