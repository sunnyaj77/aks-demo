# Just the input signature — no values here, same idea as .Values.*
# in the Helm chart having no values until values.yaml supplies them.
# Actual values go in terraform.tfvars.

variable "existing_resource_group_name" {
  description = "Resource group that already contains your ACR."
  type        = string
}

variable "existing_acr_name" {
  description = "Name of your already-existing Azure Container Registry."
  type        = string
}

variable "cluster_name" {
  description = "Name for the new AKS cluster."
  type        = string
  default     = "aks-nextjs-demo"
}

variable "node_count" {
  description = "Number of nodes in the default node pool."
  type        = number
  default     = 2
}

variable "node_vm_size" {
  description = "VM size for AKS nodes."
  type        = string
  default     = "Standard_D2s_v3"
}