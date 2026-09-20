existing_resource_group_name = "rg-nextjs-demo"
existing_acr_name            = "abhiacr07"

# github_repo already defaults to "sunnyaj77/aks-demo" in variables.tf —
# only override here if you fork this repo elsewhere.

# ---------------------------------------------------------------------------
# NOT set here on purpose — these are either secrets or personal to you,
# and this file is committed to git:
#   apim_publisher_name    (your org/team name, shown on the dev portal)
#   apim_publisher_email   (APIM's service-notification address)
#   runner_ssh_public_key  (your SSH public key)
#   github_runner_pat      (secret — see variables.tf for the scope it needs)
#
# Supply these either via a local, gitignored terraform.tfvars.local
# (terraform picks up *.auto.tfvars automatically — name it
# secrets.auto.tfvars if you want it loaded without -var-file) or as
# TF_VAR_apim_publisher_name / TF_VAR_apim_publisher_email /
# TF_VAR_runner_ssh_public_key / TF_VAR_github_runner_pat environment
# variables. In CI, infra-apply.yml now reads all four from GitHub repo
# secrets — see that workflow's env block.
# ---------------------------------------------------------------------------