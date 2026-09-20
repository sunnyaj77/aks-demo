output "get_credentials_command" {
  description = "Run this after apply to point kubectl at the new cluster."
  value       = "az aks get-credentials --resource-group ${data.azurerm_resource_group.this.name} --name ${azurerm_kubernetes_cluster.this.name}"
}

output "aks_cluster_name" {
  value = azurerm_kubernetes_cluster.this.name
}

output "resource_group_name" {
  value = data.azurerm_resource_group.this.name
}

# ---------------------------------------------------------------------------
# Values you paste into charts/nextjs-app/values.yaml and
# charts/backend-api/values.yaml once this applies (execution order step
# "Wire Key Vault + Workload Identity into the chart") — none of this is
# written to those files automatically, since they're not Terraform-managed.
# ---------------------------------------------------------------------------
output "key_vault_name" {
  description = "-> charts/*/values.yaml: secretProvider.keyvaultName"
  value       = azurerm_key_vault.this.name
}

output "key_vault_tenant_id" {
  description = "-> charts/*/values.yaml: secretProvider.tenantId"
  value       = data.azurerm_client_config.current.tenant_id
}

output "workload_uami_client_id" {
  description = "-> charts/*/values.yaml: serviceAccount.azureClientId"
  value       = azurerm_user_assigned_identity.workload.client_id
}

output "apim_gateway_url_internal" {
  description = "-> charts/nextjs-app/values.yaml: apim.gatewayUrl (internal, private DNS)"
  value       = "https://api.aks-demo.internal"
}

output "apim_developer_portal_url" {
  description = "APIM's own portal, for registering the backend API/product/subscription (execution order step 'Register the backend with APIM')."
  value       = azurerm_api_management.this.developer_portal_url
}

output "runner_nat_public_ip" {
  description = "The self-hosted runner's static egress IP — this is exactly what's already on the AKS API server's Authorized IP Ranges. Add your own IP here too (via additional_authorized_ip_ranges) if you need kubectl from your laptop."
  value       = azurerm_public_ip.runner_nat.ip_address
}

output "postgres_fqdn" {
  value = azurerm_postgresql_flexible_server.this.fqdn
}

output "redis_hostname" {
  value = azurerm_redis_cache.this.hostname
}

output "storage_account_name" {
  value = azurerm_storage_account.this.name
}

output "get_postgres_admin_password_command" {
  description = "Terraform never prints this — retrieve it from Key Vault if you need it directly (the app itself reads database-url, not this)."
  value       = "az keyvault secret show --vault-name ${azurerm_key_vault.this.name} --name database-url --query value -o tsv"
}