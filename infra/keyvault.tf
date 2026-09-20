# ---------------------------------------------------------------------------
# Key Vault — where every secret the charts already reference actually
# lives: demo-password, database-url, redis-url (backend), demo-api-key,
# apim-subscription-key (frontend). charts/*/templates/secretproviderclass.yaml
# already expect these exact object names; nothing there needs to change.
# ---------------------------------------------------------------------------
resource "azurerm_key_vault" "this" {
  name                = "kv-aksdemo-${random_string.suffix.result}"
  location            = data.azurerm_resource_group.this.location
  resource_group_name = data.azurerm_resource_group.this.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  # RBAC mode, not legacy access policies — role assignments below (not an
  # access_policy block) are what grant Terraform, the UAMI, and APIM
  # permission to read/write.
  enable_rbac_authorization = true

  public_network_access_enabled = false
}

resource "azurerm_private_endpoint" "keyvault" {
  name                = "${azurerm_key_vault.this.name}-pe"
  location            = data.azurerm_resource_group.this.location
  resource_group_name = data.azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.private_endpoints.id

  private_service_connection {
    name                           = "${azurerm_key_vault.this.name}-psc"
    private_connection_resource_id = azurerm_key_vault.this.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.keyvault.id]
  }
}

resource "azurerm_private_dns_zone" "keyvault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = data.azurerm_resource_group.this.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "keyvault" {
  name                  = "${var.cluster_name}-kv-link"
  resource_group_name  = data.azurerm_resource_group.this.name
  private_dns_zone_name = azurerm_private_dns_zone.keyvault.name
  virtual_network_id    = azurerm_virtual_network.this.id
}

# Terraform itself (the OIDC service principal infra-apply.yml logs in as)
# needs write access to create the azurerm_key_vault_secret resources
# below — RBAC mode has no implicit "creator is owner" bypass.
resource "azurerm_role_assignment" "tf_deployer_kv_secrets_officer" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# ---------------------------------------------------------------------------
# Auto-generated secret values. Nothing here is typed into tfvars by hand —
# random_password writes it into Terraform state (already sensitive by
# nature) and straight into Key Vault; retrieve any of them later with
# `az keyvault secret show --vault-name <name> --name <secret>`.
# ---------------------------------------------------------------------------
resource "random_password" "postgres_admin" {
  length           = 24
  special          = true
  override_special = "-_"
}

resource "random_password" "demo_login" {
  length  = 16
  special = false
}

resource "random_password" "demo_api_key" {
  length  = 32
  special = false
}

resource "azurerm_key_vault_secret" "demo_password" {
  name         = "demo-password"
  value        = random_password.demo_login.result
  key_vault_id = azurerm_key_vault.this.id
  depends_on   = [azurerm_role_assignment.tf_deployer_kv_secrets_officer]
}

resource "azurerm_key_vault_secret" "demo_api_key" {
  name         = "demo-api-key"
  value        = random_password.demo_api_key.result
  key_vault_id = azurerm_key_vault.this.id
  depends_on   = [azurerm_role_assignment.tf_deployer_kv_secrets_officer]
}

resource "azurerm_key_vault_secret" "database_url" {
  name         = "database-url"
  value        = "postgresql://${var.postgres_admin_username}:${urlencode(random_password.postgres_admin.result)}@${azurerm_postgresql_flexible_server.this.fqdn}:5432/${var.postgres_database_name}?sslmode=require"
  key_vault_id = azurerm_key_vault.this.id
  depends_on   = [azurerm_role_assignment.tf_deployer_kv_secrets_officer]
}

resource "azurerm_key_vault_secret" "redis_url" {
  name = "redis-url"
  # rediss:// (TLS) — matches redis.from_url()'s scheme handling in
  # backend/main.py's _redis_client(). Azure Cache for Redis requires TLS
  # by default (non-SSL port is disabled out of the box).
  value        = "rediss://:${urlencode(azurerm_redis_cache.this.primary_access_key)}@${azurerm_redis_cache.this.hostname}:${azurerm_redis_cache.this.ssl_port}/0"
  key_vault_id = azurerm_key_vault.this.id
  depends_on   = [azurerm_role_assignment.tf_deployer_kv_secrets_officer]
}

# Placeholder — the real value only exists once the backend is registered
# with APIM (a later, separate step: creating the APIM API/product/
# subscription needs the backend's internal LB address, which doesn't
# exist until the backend is Helm-deployed). ignore_changes so that manual
# `az keyvault secret set` update, once the real subscription key exists,
# doesn't get clobbered by a future `terraform apply` reverting it back to
# "not-yet-registered".
resource "azurerm_key_vault_secret" "apim_subscription_key" {
  name         = "apim-subscription-key"
  value        = "not-yet-registered"
  key_vault_id = azurerm_key_vault.this.id
  depends_on   = [azurerm_role_assignment.tf_deployer_kv_secrets_officer]

  lifecycle {
    ignore_changes = [value]
  }
}
