# APIM Dev artifacts

The `deploy-apim-dev.yml` workflow imports a Swagger/OpenAPI definition into the
existing Dev APIM service as API ID/path `backend-api`, then applies the
available policy sections. On manual runs, set `specification_path` to the
definition's path in the checked-out repository; it defaults to
`apim/dev/swagger.yaml`. The workflow fails until the sample backend URL is
replaced with the Dev backend URL.

The Sec team can replace the XML section placeholders under
`policies/backend-api/` with the inbound authentication/authorization and
rate-limit rules, backend routing, and outbound response transformations. Each
file must remain a policy section fragment (`<inbound>`, `<backend>`, or
`<outbound>`). The workflow combines present files into the complete APIM
policy document; if a section file is absent, that section inherits its parent
policy using `<base />`.

Configure these GitHub Actions variables and secrets in the `dev` environment:

- Variables: `AZURE_RESOURCE_GROUP` and `APIM_SERVICE_NAME`
- Secrets: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, and `AZURE_SUBSCRIPTION_ID`

The Azure identity must have permission to import APIs and manage API policies
on the existing APIM service. Configure its GitHub OIDC federated credential
for this repository's `dev` environment.
