# Mirrors your real AIS project's shape — no route in the sample backend
# uses this yet (see backend/main.py); it's here so the private-networking
# pattern (Standard tier, Private Endpoint, no public access) is in place
# before there's a real file to store. Safe to drop later if it stays
# unused.
resource "azurerm_storage_account" "this" {
  # Storage account names: lowercase alphanumeric only, no dashes, <=24 chars.
  name                = "aksdemo${random_string.suffix.result}"
  location            = data.azurerm_resource_group.this.location
  resource_group_name = data.azurerm_resource_group.this.name

  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  public_network_access_enabled   = false
  allow_nested_items_to_be_public = false
  min_tls_version                 = "TLS1_2"
}

resource "azurerm_private_endpoint" "storage_blob" {
  name                = "${azurerm_storage_account.this.name}-blob-pe"
  location            = data.azurerm_resource_group.this.location
  resource_group_name = data.azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "${azurerm_storage_account.this.name}-blob-psc"
    private_connection_resource_id = azurerm_storage_account.this.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.storage_blob.id]
  }
}

resource "azurerm_private_dns_zone" "storage_blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = data.azurerm_resource_group.this.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "storage_blob" {
  name                  = "${var.cluster_name}-blob-link"
  resource_group_name  = data.azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.storage_blob.name
  virtual_network_id    = azurerm_virtual_network.this.id
}
