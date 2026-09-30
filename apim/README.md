# Azure API Management

The Dev artifacts under `apim/dev/` are deployed by
`.github/workflows/deploy-apim-dev.yml` using Azure CLI. The workflow imports
the OpenAPI definition, setting its backend service URL from configuration,
then combines the inbound, backend, and outbound policy fragments and creates
or updates the API-level policy through the APIM management REST API using
`az rest`. APIM must already exist.

## Configure GitHub Actions

Add these **repository or `dev` environment variables**. Use the `dev`
environment to scope the deployment settings and enable required reviewers if
desired.

| Variable | Description |
| --- | --- |
| `APIM_RESOURCE_GROUP` | Resource group containing the APIM service |
| `APIM_SERVICE_NAME` | Existing APIM service name |
| `APIM_API_ID` | API identifier to import/update (for example, `aks-demo-backend`) |
| `APIM_API_PATH` | Gateway path for this API (for example, `backend`) |
| `APIM_API_DISPLAY_NAME` | Display name shown in APIM |
| `APIM_BACKEND_URL` | Backend base URL reachable by APIM |

Add these **GitHub Actions secrets** for the federated Azure identity:

| Secret | Description |
| --- | --- |
| `AZURE_CLIENT_ID` | Client ID of the Azure identity configured for GitHub OIDC |
| `AZURE_TENANT_ID` | Azure tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID |

Configure an Azure federated credential for the repository's GitHub Actions
subject (including the `dev` environment subject) and grant that identity the
Azure permissions needed to import APIs and manage API policies on the APIM
service. No client secret is required.

Run the workflow manually with **Actions → Deploy APIM Dev → Run workflow**,
or push changes to `apim/dev/**` on `main`. The API definition and policy files
are starter templates: replace the example API schema and TODO comments with
the actual API contract and policy XML. The inbound template intentionally
does not enforce authentication or throttling until those policies are
configured.
