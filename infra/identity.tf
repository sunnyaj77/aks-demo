# ---------------------------------------------------------------------------
# UAMI + Workload Identity — one identity, shared by both the frontend and
# backend pods (see the plan's identity section: "either works" — using one
# keeps this file shorter, since both pods only ever need the same single
# permission, Key Vault Secrets User).
#
# charts/nextjs-app/values.yaml's `secretProvider.enabled` /
# `serviceAccount.azureClientId` and charts/backend-api/values.yaml's
# equivalents are NOT set here — that's a manual/CI step per the plan's
# execution order (values.yaml isn't Terraform-managed). Once this applies,
# fill both charts in with:
#   azureClientId : azurerm_user_assigned_identity.workload.client_id  (output below)
#   keyvaultName  : azurerm_key_vault.this.name                       (output below)
#   tenantId      : data.azurerm_client_config.current.tenant_id
# ---------------------------------------------------------------------------
resource "azurerm_user_assigned_identity" "workload" {
  name                = "${var.cluster_name}-workload-uami"
  resource_group_name = data.azurerm_resource_group.this.name
  location            = data.azurerm_resource_group.this.location
}

resource "azurerm_role_assignment" "workload_kv_secrets_user" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.workload.principal_id
}

# Both Service Accounts live in the "nextjs-app" namespace (same namespace
# Flux's Namespace object already creates — see
# clusters/dev/nextjs-app-helmrelease.yaml) — the backend chart's Helm
# release, whenever it's added, should target that same namespace so this
# subject actually matches.
resource "azurerm_federated_identity_credential" "frontend" {
  name                = "nextjs-app-fic"
  resource_group_name = data.azurerm_resource_group.this.name
  parent_id           = azurerm_user_assigned_identity.workload.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.this.oidc_issuer_url
  subject             = "system:serviceaccount:nextjs-app:nextjs-app"
}

resource "azurerm_federated_identity_credential" "backend" {
  name                = "backend-api-fic"
  resource_group_name = data.azurerm_resource_group.this.name
  parent_id           = azurerm_user_assigned_identity.workload.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.this.oidc_issuer_url
  subject             = "system:serviceaccount:nextjs-app:backend-api"
}
