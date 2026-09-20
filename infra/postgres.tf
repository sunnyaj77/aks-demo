# Azure auto-creates the matching privatelink.postgres.database.azure.com
# DNS zone for a classic Private Endpoint setup, but for VNet-integrated
# (private access / delegated subnet) mode — what we're using — the
# provider requires you to create and link the zone yourself, and the
# flexible server resource takes its id directly.
resource "azurerm_private_dns_zone" "postgres" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = data.azurerm_resource_group.this.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "${var.cluster_name}-psql-link"
  resource_group_name  = data.azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = azurerm_virtual_network.this.id
}

resource "azurerm_postgresql_flexible_server" "this" {
  name                = "psql-aksdemo-${random_string.suffix.result}"
  resource_group_name = data.azurerm_resource_group.this.name
  location            = data.azurerm_resource_group.this.location

  # Burstable B1ms — confirmed: smallest SKU that supports VNet-integrated
  # private access.
  sku_name   = "B_Standard_B1ms"
  version    = "16"
  storage_mb = 32768

  administrator_login    = var.postgres_admin_username
  administrator_password = random_password.postgres_admin.result

  delegated_subnet_id = azurerm_subnet.postgres.id
  private_dns_zone_id = azurerm_private_dns_zone.postgres.id

  # No HA/replica, no geo-backup — fine for a demo, not what the real AIS
  # project would run in production.
  backup_retention_days        = 7
  geo_redundant_backup_enabled = false

  # No explicit `zone` — left for Azure to pick, same as the Portal default.

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]
}

resource "azurerm_postgresql_flexible_server_database" "app" {
  name      = var.postgres_database_name
  server_id = azurerm_postgresql_flexible_server.this.id
  # Matches Postgres's own defaults — no reason to deviate for a demo.
  collation = "en_US.utf8"
  charset   = "UTF8"
}
