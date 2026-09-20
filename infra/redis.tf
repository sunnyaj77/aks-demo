resource "azurerm_redis_cache" "this" {
  name                = "redis-aksdemo-${random_string.suffix.result}"
  location            = data.azurerm_resource_group.this.location
  resource_group_name = data.azurerm_resource_group.this.name

  # Basic C0 — confirmed: cheapest tier, still supports Private Link
  # (Private Link itself is generally available on Basic/Standard/Premium;
  # it's the older "VNet injection" mechanism that was Premium-only —
  # worth a quick check against current Azure docs at apply time in case
  # that's changed again by the time this runs).
  capacity = 0
  family   = "C"
  sku_name = "Basic"

  # TLS-only — matches the rediss:// URL written into Key Vault in
  # keyvault.tf.
  minimum_tls_version           = "1.2"
  public_network_access_enabled = false

  redis_configuration {}
}

resource "azurerm_private_endpoint" "redis" {
  name                = "${azurerm_redis_cache.this.name}-pe"
  location            = data.azurerm_resource_group.this.location
  resource_group_name = data.azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "${azurerm_redis_cache.this.name}-psc"
    private_connection_resource_id = azurerm_redis_cache.this.id
    subresource_names              = ["redisCache"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.redis.id]
  }
}

resource "azurerm_private_dns_zone" "redis" {
  name                = "privatelink.redis.cache.windows.net"
  resource_group_name = data.azurerm_resource_group.this.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "redis" {
  name                  = "${var.cluster_name}-redis-link"
  resource_group_name  = data.azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.redis.name
  virtual_network_id    = azurerm_virtual_network.this.id
}
