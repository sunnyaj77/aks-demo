data "azurerm_resource_group" "this" {
  name = var.existing_resource_group_name
}

data "azurerm_container_registry" "this" {
  name                = var.existing_acr_name
  resource_group_name = data.azurerm_resource_group.this.name
}

resource "azurerm_kubernetes_cluster" "this" {
  name                = var.cluster_name
  resource_group_name = data.azurerm_resource_group.this.name
  location            = data.azurerm_resource_group.this.location
  dns_prefix          = var.cluster_name

  default_node_pool {
    name       = "system"
    node_count = var.node_count
    vm_size    = var.node_vm_size
  }

  identity {
    type = "SystemAssigned"
  }
}

# Terraform's version of the "--attach-acr" flag / the Integrations-tab
# dropdown in the Portal wizard — grants the cluster's node identity
# pull access to the registry you already created by hand.
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = data.azurerm_container_registry.this.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
}