data "azurerm_resource_group" "this" {
  name = var.existing_resource_group_name
}

data "azurerm_container_registry" "this" {
  name                = var.existing_acr_name
  resource_group_name = data.azurerm_resource_group.this.name
}

# NOTE: vnet_subnet_id, network_profile, oidc_issuer_enabled and
# workload_identity_enabled cannot be changed in place on an already-live
# cluster — Azure forces a replace. That's expected and fine here (this
# demo cluster gets destroyed between sessions — see infra-destroy.yml —
# so there's no live workload this would disrupt), but flagging it in case
# this ever runs against a cluster you actually want to keep.
resource "azurerm_kubernetes_cluster" "this" {
  name                = var.cluster_name
  resource_group_name = data.azurerm_resource_group.this.name
  location            = data.azurerm_resource_group.this.location
  dns_prefix          = var.cluster_name

  # Custom VNet, Azure CNI Overlay — replaces the old kubenet default.
  # "Overlay" mode means pods get addresses from a separate, non-routed
  # pod_cidr (var.aks_pod_cidr) instead of consuming real subnet IPs, so
  # snet-aks only has to be large enough for node IPs.
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    pod_cidr            = var.aks_pod_cidr
  }

  default_node_pool {
    name           = "system"
    node_count     = var.node_count
    vm_size        = var.node_vm_size
    vnet_subnet_id = azurerm_subnet.aks.id
  }

  identity {
    type = "SystemAssigned"
  }

  # AKS API server exposure — confirmed: stays public, but locked down to
  # the runner VM's static NAT-Gateway IP (network.tf) plus anything you
  # add to additional_authorized_ip_ranges. This is what makes the
  # self-hosted-VM CI runner decision work without a private-cluster /
  # jumpbox setup.
  api_server_access_profile {
    authorized_ip_ranges = concat(
      ["${azurerm_public_ip.runner_nat.ip_address}/32"],
      var.additional_authorized_ip_ranges,
    )
  }

  # What lets a pod authenticate to Key Vault via the UAMI + federated
  # credential in identity.tf, with zero stored credentials.
  oidc_issuer_enabled      = true
  workload_identity_enabled = true

  # Installs the Secrets Store CSI driver + Azure provider as a managed
  # add-on — charts/*/templates/secretproviderclass.yaml already assume
  # this exists, it's just been switched off (secretProvider.enabled:
  # false) until now.
  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
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