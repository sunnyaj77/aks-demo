terraform {
  required_version = ">= 1.7.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 3.110" }
    # Used to auto-generate the Postgres admin password, the demo login
    # password, and the demo-api-key secret — so nothing secret has to be
    # invented by hand or typed into tfvars. Also used for the storage
    # account / Key Vault / Redis / Postgres / APIM name suffix, since all
    # five need a globally-unique name and re-typing a suffix five times
    # invites a typo-driven mismatch.
    random = { source = "hashicorp/random", version = "~> 3.6" }
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
  skip_provider_registration = true
  features {
    key_vault {
      # This is a demo environment that gets destroyed and rebuilt — skip
      # the 7/90-day soft-delete recovery dance on `terraform destroy` so a
      # re-apply under the same Key Vault name doesn't collide with a
      # soft-deleted leftover from last time.
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
}

# Distinguishes this Terraform-authenticated identity (the OIDC service
# principal infra-apply.yml logs in as) from the UAMI the pods use later —
# needed below to grant Terraform itself permission to write secrets into
# the new Key Vault (RBAC mode has no "owner can always write" bypass).
data "azurerm_client_config" "current" {}