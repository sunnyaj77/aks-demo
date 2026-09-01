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