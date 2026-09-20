# Storage Account, Key Vault, Redis, Postgres, and APIM names all have to be
# globally unique across Azure, not just within this resource group. One
# shared 4-character suffix (stable across applies once created, since it
# lives in state) keeps all five names related and avoids reserving/typing
# five separate suffixes by hand.
resource "random_string" "suffix" {
  length  = 4
  special = false
  upper   = false
}
