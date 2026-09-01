terraform {
  required_version = ">= 1.7.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 3.110" }
  }
  backend "azurerm" {
    resource_group_name  = "terraform-state"
    storage_account_name = "abhijtfstate"
    container_name        = "tfstate"
    key                    = "aks-nextjs-demo.tfstate"
  }
}

provider "azurerm" {
  use_oidc = true
  resource_provider_registrations = "none"
  features {}
}