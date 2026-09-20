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
  default     = "Standard_B2s_v2"
}

# ---------------------------------------------------------------------------
# Networking — one VNet, five subnets. See the plan's architecture diagram:
# runner / private-endpoints / postgres-delegated / apim all stack inside
# the same VNet as the AKS node subnet. Non-overlapping /28-/22 ranges
# carved out of a single 10.60.0.0/16 so there's room to grow any one of
# them later without a re-plan.
# ---------------------------------------------------------------------------
variable "vnet_address_space" {
  description = "Address space for the new VNet everything in this plan lives in."
  type        = string
  default     = "10.60.0.0/16"
}

variable "aks_subnet_cidr" {
  description = "AKS node subnet. Azure CNI Overlay is used (see main.tf), so this only needs to fit node IPs, not pod IPs — pods get addresses from the overlay's own pod_cidr instead."
  type        = string
  default     = "10.60.0.0/22"
}

variable "aks_pod_cidr" {
  description = "Overlay pod CIDR (never routed on the VNet itself) for Azure CNI Overlay mode."
  type        = string
  default     = "10.244.0.0/16"
}

variable "runner_subnet_cidr" {
  description = "Subnet for the self-hosted CI runner VM."
  type        = string
  default     = "10.60.4.0/28"
}

variable "pe_subnet_cidr" {
  description = "Shared subnet for Private Endpoints: Key Vault, Storage, Redis."
  type        = string
  default     = "10.60.4.16/28"
}

variable "postgres_subnet_cidr" {
  description = "Delegated subnet for PostgreSQL Flexible Server's VNet-integrated (private access) mode. Must not be shared with anything else — Azure requirement."
  type        = string
  default     = "10.60.4.32/28"
}

variable "apim_subnet_cidr" {
  description = "Dedicated subnet for APIM's VNet integration. Must not be shared — Azure requirement. Sized /27 per Microsoft's recommended (not bare minimum) size for a single-unit Developer instance."
  type        = string
  default     = "10.60.4.64/27"
}

variable "additional_authorized_ip_ranges" {
  description = "Extra CIDRs to allow through to the AKS API server alongside the runner VM's static egress IP — e.g. your own office/home IP, so kubectl keeps working from your laptop while you're still setting this up. Each entry needs a /32 (or wider) suffix, e.g. \"203.0.113.7/32\"."
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Data layer
# ---------------------------------------------------------------------------
variable "postgres_admin_username" {
  description = "PostgreSQL Flexible Server admin login."
  type        = string
  default     = "pgadmin"
}

variable "postgres_database_name" {
  description = "Name of the application database created on the Flexible Server."
  type        = string
  default     = "appdb"
}

# ---------------------------------------------------------------------------
# APIM
# ---------------------------------------------------------------------------
variable "apim_publisher_name" {
  description = "Shown on the APIM developer portal / emails. No default on purpose — pick something real for your org."
  type        = string
}

variable "apim_publisher_email" {
  description = "APIM sends service-notification emails here (capacity, certificate expiry, etc). No default on purpose."
  type        = string
}

# ---------------------------------------------------------------------------
# Self-hosted CI runner VM
# ---------------------------------------------------------------------------
variable "runner_vm_size" {
  description = "VM size for the self-hosted GitHub Actions runner. Small — it only builds/pushes an image and runs helm upgrade, no heavy compute."
  type        = string
  default     = "Standard_B2s"
}

variable "runner_admin_username" {
  description = "Admin username for the runner VM (SSH access, break-glass only — the runner agent itself needs no interactive login)."
  type        = string
  default     = "azureuser"
}

variable "runner_ssh_public_key" {
  description = "Your SSH public key, for break-glass access to the runner VM. No default on purpose — this is *your* key, not a shared one."
  type        = string
}

variable "github_repo" {
  description = "GitHub \"owner/repo\" this runner registers itself against, e.g. \"sunnyaj77/aks-demo\"."
  type        = string
  default     = "sunnyaj77/aks-demo"
}

variable "github_runner_pat" {
  description = <<-EOT
    A GitHub PAT used ONCE at boot to call GitHub's REST API for a
    short-lived runner-registration token (registration tokens themselves
    expire in ~1 hour, so cloud-init fetches a fresh one rather than being
    handed a stale one). Needs "Administration: read & write" on this repo
    (fine-grained PAT) or classic "repo" scope. Treat it like any other
    secret: pass it via TF_VAR_github_runner_pat / a CI secret, never commit
    it to terraform.tfvars.
  EOT
  type        = string
  sensitive   = true
}