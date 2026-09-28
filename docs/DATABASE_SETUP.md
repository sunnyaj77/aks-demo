# Azure PostgreSQL + Microsoft Entra Database Setup

This guide configures a **dedicated Azure Database for PostgreSQL Flexible Server database** for:

- GitHub Actions/Alembic schema migrations through a dedicated UAMI.
- AKS application runtime access through a separate UAMI.
- Least-privilege PostgreSQL roles and database permissions.

The examples use these placeholders:

| Placeholder | Meaning | Example |
|---|---|---|
| `<SERVER_FQDN>` | PostgreSQL server FQDN | `myserver.postgres.database.azure.com` |
| `<PROJECT_DB>` | Dedicated project database | `projectdb` |
| `<MIGRATION_UAMI_NAME>` | UAMI used by GitHub Actions | `UAMI-testAC` |
| `<MIGRATION_UAMI_OBJECT_ID>` | UAMI service-principal object ID | `00000000-0000-0000-0000-000000000000` |
| `<APP_UAMI_NAME>` | UAMI used by AKS application pods | `UAMI-appProd` |
| `<APP_UAMI_OBJECT_ID>` | Application UAMI object ID | `00000000-0000-0000-0000-000000000000` |

Replace every placeholder before running commands. Do not copy production values into source control.

## Important distinction: Azure RBAC versus PostgreSQL permissions

There are two different authorization layers:

1. **Azure control-plane permissions**: needed to configure the server, set the Microsoft Entra administrator, assign identities to Azure resources, or configure federated credentials.
2. **PostgreSQL data-plane permissions**: needed to connect to a database and read, write, or change schema objects.

For normal database access, the UAMI does **not** need a broad Azure RBAC role such as Contributor or Owner on the PostgreSQL server. After Microsoft Entra authentication is enabled and the UAMI is created as a PostgreSQL principal, access is controlled by PostgreSQL `GRANT` statements and role membership.

The one-time setup must be performed by a PostgreSQL administrator or Microsoft Entra administrator. The migration UAMI should not be made the server's Microsoft Entra administrator in production.

## Architecture

```text
GitHub Actions
    │ OIDC -> Azure login -> PostgreSQL Entra access token
    ▼
<MIGRATION_UAMI_NAME>
    │ member of project_migration
    ▼
Dedicated database: <PROJECT_DB>
    └── schema: public
        ├── CONNECT
        ├── USAGE
        └── CREATE + migration object privileges

AKS application pods
    │ Workload Identity -> PostgreSQL Entra access token
    ▼
<APP_UAMI_NAME>
    │ member of project_app
    ▼
Dedicated database: <PROJECT_DB>
    └── schema: public
        └── runtime DML only
```

Use separate UAMIs for migrations and application runtime. The application UAMI should not receive schema `CREATE` or migration privileges.

## Prerequisites

- Azure Database for PostgreSQL Flexible Server is provisioned.
- Microsoft Entra authentication is enabled on the server.
- A Microsoft Entra administrator is configured for the server.
- The project has its own dedicated database, `<PROJECT_DB>`.
- The operator can connect as the PostgreSQL administrator or Microsoft Entra administrator.
- The UAMI has already been created in Microsoft Entra ID.
- GitHub Actions or AKS has the appropriate OIDC/workload identity configuration.
- Network rules, private DNS, and firewall/NSG rules allow the client to reach PostgreSQL.

Microsoft Entra authentication uses an access token as the PostgreSQL password. The token resource used by this repository's workflow is `https://ossrdbms-aad.database.windows.net`.

## Step 0: Configure and verify the Azure identity layer

### 0.1 Confirm the server's Microsoft Entra authentication configuration

In the Azure portal, open the PostgreSQL Flexible Server and check **Authentication**. Confirm that Microsoft Entra authentication is enabled and that an Entra administrator is configured.

The Entra administrator is a setup/admin identity. It has elevated database capabilities and should not be used for normal application traffic or routine migrations.

### 0.2 Confirm the UAMI identity details

Retrieve the UAMI's object ID and client ID:

```bash
az identity show \
  --resource-group <RESOURCE_GROUP> \
  --name <MIGRATION_UAMI_NAME> \
  --query '{name:name,clientId:clientId,principalId:principalId}' \
  --output table
```

Use the `principalId` as `<MIGRATION_UAMI_OBJECT_ID>` if you use the object-ID-based PostgreSQL principal command. This is the managed identity's service-principal object ID, not the client ID.

### 0.3 Azure RBAC needed for setup

The person or deployment identity performing setup may need Azure permissions to:

- Configure Microsoft Entra authentication or the server's Entra administrator.
- Assign a UAMI to an Azure resource.
- Configure GitHub federated credentials or AKS workload identity.
- Read the PostgreSQL server or UAMI resource.

Those permissions are not database permissions. Do not grant the migration UAMI `Owner` or `Contributor` merely so it can connect to PostgreSQL.

## Step 1: Create the UAMI as a Microsoft Entra PostgreSQL principal

Connect to the built-in `postgres` database as the configured Microsoft Entra administrator. Azure PostgreSQL's `pgaadauth_create_principal` function must be run in the `postgres` database, not only in the project database.

### Option A: Create by UAMI display name

Use this when the UAMI display name is unique in the tenant:

```sql
SELECT *
FROM pg_catalog.pgaadauth_create_principal(
  '<MIGRATION_UAMI_NAME>',
  false, -- regular user, not a PostgreSQL admin
  false  -- do not require MFA for this service identity
);
```

For the application UAMI, repeat the command with `<APP_UAMI_NAME>`:

```sql
SELECT *
FROM pg_catalog.pgaadauth_create_principal(
  '<APP_UAMI_NAME>',
  false,
  false
);
```

### Option B: Create by Microsoft Entra object ID

Use this when the display name is not unique or you want an explicit identity mapping:

```sql
SELECT *
FROM pg_catalog.pgaadauth_create_principal_with_oid(
  '<MIGRATION_UAMI_NAME>',
  '<MIGRATION_UAMI_OBJECT_ID>',
  'service', -- service principal or managed identity
  false,    -- regular user, not a PostgreSQL admin
  false     -- do not require MFA for this service identity
);
```

For the application UAMI:

```sql
SELECT *
FROM pg_catalog.pgaadauth_create_principal_with_oid(
  '<APP_UAMI_NAME>',
  '<APP_UAMI_OBJECT_ID>',
  'service',
  false,
  false
);
```

### Verify the Entra principal mapping

Run this in the `postgres` database:

```sql
SELECT rolename, principaltype, objectid, tenantid, isadmin
FROM pg_catalog.pgaadauth_list_principals(false)
WHERE rolename IN ('<MIGRATION_UAMI_NAME>', '<APP_UAMI_NAME>');
```

Expected result: each UAMI appears as a non-admin `service` principal with the expected object ID.

If the principal already exists, do not recreate it. Continue with the project database permissions below.

## Step 2: Connect to the dedicated project database

The following role and privilege commands must be run while connected to `<PROJECT_DB>`:

```bash
psql \
  "host=<SERVER_FQDN> port=5432 dbname=<PROJECT_DB> user=<ENTRA_ADMIN_NAME> sslmode=require"
```

The exact Entra administrator username is tenant-specific. When using a token with `psql`, set the token as the password:

```bash
export PGPASSWORD="$(az account get-access-token \
  --resource https://ossrdbms-aad.database.windows.net \
  --query accessToken --output tsv)"
```

Never print the token or commit it to a file.

## Step 3: Create the least-privilege migration role

`project_migration` is a non-login PostgreSQL group role. It is not an Entra identity and does not need an Azure RBAC assignment.

Run this in `<PROJECT_DB>` as the database administrator:

```sql
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_roles WHERE rolname = 'project_migration'
  ) THEN
    CREATE ROLE project_migration
      NOLOGIN
      NOSUPERUSER
      NOCREATEDB
      NOCREATEROLE
      NOREPLICATION;
  END IF;
END
$$;

-- Allow the migration UAMI to enter this dedicated database.
GRANT CONNECT ON DATABASE <PROJECT_DB> TO project_migration;

-- Required for Alembic to access and create objects in public.
GRANT USAGE ON SCHEMA public TO project_migration;
GRANT CREATE ON SCHEMA public TO project_migration;

-- Required when migrations operate on objects that already exist.
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO project_migration;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO project_migration;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO project_migration;
```

### Default privileges for future objects

Default privileges apply to objects created by a particular object owner. Run the following as the role that will own migration-created objects, normally the Entra migration principal or the deployment owner:

```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL PRIVILEGES ON TABLES TO project_migration;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL PRIVILEGES ON SEQUENCES TO project_migration;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL PRIVILEGES ON FUNCTIONS TO project_migration;
```

`GRANT ALL` does not transfer ownership. If Alembic must alter or drop tables created by another owner, use one consistent migration owner or explicitly transfer ownership during a controlled database setup. Do not solve this by making the UAMI a superuser.

## Step 4: Assign the migration role to the UAMI

Run this in `<PROJECT_DB>`:

```sql
GRANT project_migration TO "<MIGRATION_UAMI_NAME>";

-- Ensure the UAMI inherits privileges from granted roles.
ALTER ROLE "<MIGRATION_UAMI_NAME>" INHERIT;
```

Do not set `NOINHERIT` on the connecting UAMI. The group role itself remains `NOLOGIN`.

## Step 5: Create the runtime application role

The AKS runtime role should not be able to create or alter schema objects:

```sql
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_roles WHERE rolname = 'project_app'
  ) THEN
    CREATE ROLE project_app
      NOLOGIN
      NOSUPERUSER
      NOCREATEDB
      NOCREATEROLE
      NOREPLICATION;
  END IF;
END
$$;

GRANT CONNECT ON DATABASE <PROJECT_DB> TO project_app;
GRANT USAGE ON SCHEMA public TO project_app;
GRANT SELECT, INSERT, UPDATE, DELETE
  ON ALL TABLES IN SCHEMA public TO project_app;
GRANT USAGE, SELECT
  ON ALL SEQUENCES IN SCHEMA public TO project_app;

GRANT project_app TO "<APP_UAMI_NAME>";
ALTER ROLE "<APP_UAMI_NAME>" INHERIT;
```

Configure default privileges for the role that owns future application tables:

```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO project_app;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO project_app;
```

## Step 6: Optional hardening for a dedicated database

Only perform these commands after confirming that your administration and application paths still have the required access:

```sql
-- Prevent unrelated PostgreSQL roles from connecting to the project database.
REVOKE CONNECT ON DATABASE <PROJECT_DB> FROM PUBLIC;

-- Prevent the default PUBLIC role from creating objects in public.
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
```

If other legitimate roles need access, explicitly grant them `CONNECT` and the required schema/object privileges.

## Step 7: Verify the effective permissions

Run these checks in `<PROJECT_DB>`:

```sql
SELECT
  rolname,
  rolinherit,
  rolcanlogin,
  rolsuper,
  rolcreatedb,
  rolcreaterole
FROM pg_roles
WHERE rolname IN (
  '<MIGRATION_UAMI_NAME>',
  '<APP_UAMI_NAME>',
  'project_migration',
  'project_app'
)
ORDER BY rolname;
```

Check role membership:

```sql
SELECT
  member::regrole AS member,
  roleid::regrole AS granted_role
FROM pg_auth_members
WHERE roleid IN (
  'project_migration'::regrole,
  'project_app'::regrole
)
ORDER BY granted_role, member;
```

Check the migration UAMI's effective permissions:

```sql
SELECT
  has_database_privilege(
    '<MIGRATION_UAMI_NAME>',
    '<PROJECT_DB>',
    'CONNECT'
  ) AS can_connect,
  has_schema_privilege(
    '<MIGRATION_UAMI_NAME>',
    'public',
    'USAGE'
  ) AS can_use_schema,
  has_schema_privilege(
    '<MIGRATION_UAMI_NAME>',
    'public',
    'CREATE'
  ) AS can_create_in_schema;
```

Expected values for the migration UAMI:

```text
 can_connect | can_use_schema | can_create_in_schema
-------------+----------------+---------------------
 true        | true           | true
```

Check the runtime UAMI:

```sql
SELECT
  has_database_privilege('<APP_UAMI_NAME>', '<PROJECT_DB>', 'CONNECT')
    AS can_connect,
  has_schema_privilege('<APP_UAMI_NAME>', 'public', 'USAGE')
    AS can_use_schema,
  has_schema_privilege('<APP_UAMI_NAME>', 'public', 'CREATE')
    AS can_create_in_schema;
```

The runtime UAMI should have `can_connect = true`, `can_use_schema = true`, and `can_create_in_schema = false`.

## Step 8: Test connectivity without running migrations

To test only network, authentication, and database connectivity, run a query that does not modify the schema:

```bash
export PGPASSWORD="$(az account get-access-token \
  --resource https://ossrdbms-aad.database.windows.net \
  --query accessToken --output tsv)"

psql \
  "host=<SERVER_FQDN> port=5432 dbname=<PROJECT_DB> user=<MIGRATION_UAMI_NAME> sslmode=require" \
  -v ON_ERROR_STOP=1 \
  -c 'SELECT current_user, current_database(), inet_server_addr();'
```

A successful `SELECT` confirms connectivity and authentication. It does not confirm migration DDL permissions. Test the latter separately with the effective privilege query above or in a non-production database.

The repository workflow also performs a non-mutating `SELECT 1` connectivity check before invoking Alembic. If the workflow reaches `CREATE TABLE alembic_version`, connectivity and authentication have already succeeded; a failure there is a database authorization/ownership issue rather than a network connection failure.

## Current error: `permission denied for schema public`

For the current Alembic error, verify all of the following:

1. The UAMI was created as a Microsoft Entra PostgreSQL principal.
2. The principal was created in the built-in `postgres` database.
3. The role grants were run while connected to the dedicated project database.
4. The workflow's `PGUSER` exactly matches the PostgreSQL role name, including case.
5. The migration UAMI is a member of `project_migration`.
6. The UAMI has `INHERIT` enabled.
7. `project_migration` has `CONNECT` on the dedicated database.
8. `project_migration` has both `USAGE` and `CREATE` on the `public` schema.
9. If the table already exists, the migration identity has the required privileges or owns the object.

Useful checks:

```sql
SELECT current_database();
SELECT rolname, rolinherit, rolcanlogin
FROM pg_roles
WHERE rolname = '<MIGRATION_UAMI_NAME>';

SELECT has_schema_privilege(
  '<MIGRATION_UAMI_NAME>',
  'public',
  'USAGE,CREATE'
);
```

Do not grant superuser, `CREATEROLE`, or `CREATEDB` to the migration UAMI to resolve this error.

## Production checklist

- [ ] Microsoft Entra authentication is enabled on the PostgreSQL Flexible Server.
- [ ] A separate Entra administrator is configured for one-time setup.
- [ ] The migration UAMI is mapped with `pgaadauth_create_principal(..., false, false)`.
- [ ] The application UAMI is mapped as a separate non-admin principal.
- [ ] The project uses a dedicated database.
- [ ] `project_migration` is `NOLOGIN`, `NOSUPERUSER`, `NOCREATEDB`, and `NOCREATEROLE`.
- [ ] `project_app` has runtime DML only and no schema `CREATE` privilege.
- [ ] No broad Azure RBAC role was granted to the UAMI just for database connectivity.
- [ ] GitHub OIDC and AKS workload identity are restricted to the intended subjects/namespaces.
- [ ] Network access to the PostgreSQL server is restricted appropriately.
- [ ] Migration execution is protected by deployment approvals and environment controls.
- [ ] Role membership and schema privileges are reviewed periodically.

## References

- [Use Microsoft Entra ID authentication in Azure Database for PostgreSQL Flexible Server](https://learn.microsoft.com/en-us/azure/postgresql/security/security-entra-configure)
- [Manage Microsoft Entra roles in Azure Database for PostgreSQL Flexible Server](https://learn.microsoft.com/en-us/azure/postgresql/security/security-manage-entra-users)
- [Connect with a managed identity](https://learn.microsoft.com/en-us/azure/postgresql/security/security-connect-with-managed-identity)
- [Access management in Azure Database for PostgreSQL Flexible Server](https://learn.microsoft.com/en-us/azure/postgresql/security/security-access-control)
- [PostgreSQL role management](https://www.postgresql.org/docs/current/user-manag.html)
- [PostgreSQL privileges](https://www.postgresql.org/docs/current/ddl-priv.html)
