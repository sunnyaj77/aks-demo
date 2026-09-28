# PostgreSQL Database Setup Guide

## Overview

This guide provides step-by-step instructions for setting up PostgreSQL roles and permissions for your AKS demo project. It covers both CI/CD (GitHub Actions) migration workflows and production runtime application access.

**Key Principle**: Follow least privilege - each service gets only the permissions it needs.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Architecture Overview](#architecture-overview)
3. [Step 1: Create Migration Admin Role](#step-1-create-migration-admin-role)
4. [Step 2: Create Application User Role](#step-2-create-application-user-role)
5. [Step 3: Grant Roles to UAMI Users](#step-3-grant-roles-to-uami-users)
6. [Step 4: Verification](#step-4-verification)
7. [Troubleshooting](#troubleshooting)
8. [Production Deployment](#production-deployment)

---

## Prerequisites

- Access to the PostgreSQL server as a **superuser** (e.g., `postgres` user)
- Your dedicated project database name and UAMI user names
- `psql` CLI tool installed (or Azure Portal Query Editor)

**Database Details** (for this project):
```
PGHOST: <your-postgres-server>.postgres.database.azure.com
PGDATABASE: <your-dedicated-db-name>
PGUSER (superuser): postgres
PGPORT: 5432
```

---

## Architecture Overview

### Role Hierarchy

```
┌─────────────────────────────────────────────────────┐
│         PostgreSQL Database (your-dedicated-db)      │
├─────────────────────────────────────────────────────┤
│                                                     │
├── Role: migration_admin                            │
│   ├─ Used by: GitHub Actions (Alembic migrations) │
│   ├─ Permissions: DDL (schema/table creation)      │
│   └─ Member: UAMI-testAC                           │
│                                                     │
├── Role: app_user                                   │
│   ├─ Used by: AKS pods (runtime app)              │
│   ├─ Permissions: DML only (SELECT/INSERT/etc)    │
│   └─ Member: UAMI-appProd                          │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### Authentication Flow

**GitHub Actions (Migrations)**:
```
GitHub Workflow → Azure Login (UAMI-testAC) → Entra Token → 
PostgreSQL (as UAMI-testAC@tenant) → inherits migration_admin → Run Alembic
```

**AKS Runtime (Application)**:
```
AKS Pod → Workload Identity (UAMI-appProd) → Entra Token → 
PostgreSQL (as UAMI-appProd@tenant) → inherits app_user → Query Database
```

---

## Step 1: Create Migration Admin Role

This role is used by GitHub Actions to perform database migrations (Alembic).

### Connect to PostgreSQL

Use one of these methods:

**Option A: Using Azure Portal**
1. Go to Azure Portal → PostgreSQL Server
2. Click "Query editor (preview)"
3. Sign in as superuser

**Option B: Using psql CLI**
```bash
psql -h your-postgres-server.postgres.database.azure.com \
     -U postgres \
     -d your-dedicated-db \
     -p 5432
```

### Execute the SQL

Run the following SQL commands in your PostgreSQL database:

```sql
-- =============================================================================
-- Create Migration Admin Role
-- Purpose: Used by CI/CD pipelines (GitHub Actions) for Alembic migrations
-- Permissions: DDL operations (CREATE/ALTER/DROP tables, sequences, etc)
-- =============================================================================

CREATE ROLE migration_admin WITH
  NOINHERIT        -- Does not automatically inherit permissions
  NOCREATEROLE     -- Cannot create new roles
  NOCREATEDB       -- Cannot create databases
  NOLOGIN;         -- Cannot log in directly (only via GRANT to user)

-- Grant schema-level permissions
GRANT USAGE ON SCHEMA public TO migration_admin;
GRANT CREATE ON SCHEMA public TO migration_admin;

-- Grant table and sequence permissions
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO migration_admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO migration_admin;

-- Set defaults for future objects (created by migrations)
ALTER DEFAULT PRIVILEGES IN SCHEMA public 
  GRANT ALL ON TABLES TO migration_admin;

ALTER DEFAULT PRIVILEGES IN SCHEMA public 
  GRANT ALL ON SEQUENCES TO migration_admin;

-- Log the successful creation
SELECT 'migration_admin role created successfully' AS status;
```

**Expected Output**:
```
CREATE ROLE
GRANT
GRANT
GRANT
GRANT
ALTER DEFAULT PRIVILEGES
ALTER DEFAULT PRIVILEGES
 status
─────────────────────────────────────
 migration_admin role created successfully
```

---

## Step 2: Create Application User Role

This role is used by your AKS application pods at runtime. It has minimal permissions (least privilege).

### Execute the SQL

Run the following SQL commands:

```sql
-- =============================================================================
-- Create Application User Role
-- Purpose: Used by AKS pods at runtime for application queries
-- Permissions: DML only (SELECT, INSERT, UPDATE, DELETE) - No DDL
-- =============================================================================

CREATE ROLE app_user WITH
  NOINHERIT        -- Does not automatically inherit permissions
  NOCREATEROLE     -- Cannot create roles
  NOCREATEDB       -- Cannot create databases
  NOLOGIN;         -- Cannot log in directly

-- Grant schema-level permissions
GRANT USAGE ON SCHEMA public TO app_user;

-- Grant DML permissions (read and write, but not modify schema)
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_user;

-- Set defaults for future objects
ALTER DEFAULT PRIVILEGES IN SCHEMA public 
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_user;

ALTER DEFAULT PRIVILEGES IN SCHEMA public 
  GRANT USAGE, SELECT ON SEQUENCES TO app_user;

-- Log the successful creation
SELECT 'app_user role created successfully' AS status;
```

**Expected Output**:
```
CREATE ROLE
GRANT
GRANT
GRANT
ALTER DEFAULT PRIVILEGES
ALTER DEFAULT PRIVILEGES
 status
────────────────────────────────────
 app_user role created successfully
```

---

## Step 3: Grant Roles to UAMI Users

Now assign the roles to your actual UAMI users that will authenticate via Entra ID.

### Grant migration_admin to GitHub Actions UAMI

Run this SQL:

```sql
-- =============================================================================
-- Grant migration_admin role to GitHub Actions UAMI
-- This allows the CI/CD pipeline to run Alembic migrations
-- =============================================================================

-- Assign the migration_admin role to the GitHub Actions UAMI
GRANT migration_admin TO "UAMI-testAC";

-- Verify the grant
SELECT 
  'UAMI-testAC' AS uami_user,
  'migration_admin' AS role_assigned,
  'GitHub Actions - Alembic Migrations' AS purpose;

-- Confirm role membership
SELECT 
  member::regrole::text AS member_user,
  roleid::regrole::text AS role_name
FROM pg_auth_members
WHERE roleid = (SELECT oid FROM pg_roles WHERE rolname = 'migration_admin');
```

**Expected Output**:
```
  uami_user    │    role_assigned    │            purpose
───────────────┼──────────────────────┼──────────────────────────────
 UAMI-testAC   │ migration_admin      │ GitHub Actions - Alembic Migrations
 
 member_user   │    role_name
───────────────┼──────────────────────
 UAMI-testAC   │ migration_admin
```

### Grant app_user to AKS Application UAMI

Run this SQL:

```sql
-- =============================================================================
-- Grant app_user role to AKS Runtime UAMI
-- This allows the application pods to query the database at runtime
-- =============================================================================

-- Assign the app_user role to the AKS application UAMI
GRANT app_user TO "UAMI-appProd";

-- Verify the grant
SELECT 
  'UAMI-appProd' AS uami_user,
  'app_user' AS role_assigned,
  'AKS Runtime - Application Queries' AS purpose;

-- Confirm role membership
SELECT 
  member::regrole::text AS member_user,
  roleid::regrole::text AS role_name
FROM pg_auth_members
WHERE roleid = (SELECT oid FROM pg_roles WHERE rolname = 'app_user');
```

**Expected Output**:
```
  uami_user    │ role_assigned │         purpose
───────────────┼───────────────┼──────────────────────────────
 UAMI-appProd  │ app_user      │ AKS Runtime - Application Queries

 member_user   │  role_name
───────────────┼──────────────
 UAMI-appProd  │ app_user
```

---

## Step 4: Verification

Run these queries to verify everything is set up correctly:

### Verify All Roles Exist

```sql
-- List all custom roles
SELECT 
  rolname AS role_name,
  rolsuper AS is_superuser,
  rolinherit AS can_inherit,
  rolcanlogin AS can_login,
  rolcreatedb AS can_create_db,
  rolcreaterole AS can_create_role
FROM pg_roles
WHERE rolname IN ('migration_admin', 'app_user')
ORDER BY rolname;
```

**Expected Output**:
```
    role_name    │ is_superuser │ can_inherit │ can_login │ can_create_db │ can_create_role
────────────────┼──────────────┼─────────────┼───────────┼───────────────┼─────────────────
 app_user        │ f            │ f           │ f         │ f             │ f
 migration_admin │ f            │ f           │ f         │ f             │ f
```

### Verify Role Membership

```sql
-- Show which UAMIs are members of which roles
SELECT 
  member::regrole::text AS uami_user,
  roleid::regrole::text AS role_name
FROM pg_auth_members
WHERE roleid::regrole::text IN ('migration_admin', 'app_user')
ORDER BY roleid, member;
```

**Expected Output**:
```
    uami_user    │    role_name
────────────────┼──────────────────
 UAMI-appProd   │ app_user
 UAMI-testAC    │ migration_admin
```

### Verify Schema Permissions

```sql
-- Check migration_admin permissions on public schema
SELECT 
  'migration_admin' AS role,
  grantee,
  privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public' AND grantee = 'migration_admin'
ORDER BY privilege_type;

-- Check app_user permissions on public schema
SELECT 
  'app_user' AS role,
  grantee,
  privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public' AND grantee = 'app_user'
ORDER BY privilege_type;
```

**Expected Output for migration_admin**:
```
       role       │     grantee     │ privilege_type
─────────────────┼─────────────────┼────────────────
 migration_admin  │ migration_admin  │ ALL
 migration_admin  │ migration_admin  │ CREATE
 migration_admin  │ migration_admin  │ USAGE
```

**Expected Output for app_user**:
```
   role   │  grantee  │ privilege_type
──────────┼───────────┼────────────────
 app_user │ app_user  │ DELETE
 app_user │ app_user  │ INSERT
 app_user │ app_user  │ SELECT
 app_user │ app_user  │ UPDATE
 app_user │ app_user  │ USAGE
```

---

## Troubleshooting

### Issue: "permission denied for schema public" during migrations

**Cause**: The `UAMI-testAC` user doesn't have the `migration_admin` role.

**Solution**:
```sql
-- Re-verify the grant
GRANT migration_admin TO "UAMI-testAC";

-- Force refresh role cache
SELECT pg_reload_conf();
```

### Issue: Application can't create tables at runtime

**Expected Behavior**: This is correct! The `app_user` role intentionally **cannot** create tables.

**Solution**: Only Alembic (via `migration_admin`) should create tables. If your app needs to create tables, re-evaluate your design.

### Issue: "role does not exist" error

**Cause**: Role name has incorrect case or special characters.

**Solution**: Double-check exact role names:
```sql
-- List all roles in your database
SELECT rolname FROM pg_roles ORDER BY rolname;
```

### Issue: Can't connect as UAMI user

**Cause**: 
- Azure Entra token expired or invalid
- Firewall rules blocking access
- Database server has public network access disabled

**Solution**:
```bash
# Refresh Entra token
az account get-access-token --resource https://ossrdbms-aad.database.windows.net

# Verify firewall rules
az postgres server firewall-rule list --resource-group $RG --server-name $SERVER
```

---

## Production Deployment

### Automated Setup Using Script

Instead of manual SQL, automate this using a script in CI/CD:

Create `scripts/setup-postgres-roles.sql`:

```sql
-- PostgreSQL Role Setup for AKS Demo Project
-- Usage: psql -h $PGHOST -U postgres -d $PGDATABASE -f scripts/setup-postgres-roles.sql

-- Migration Admin Role (CI/CD)
CREATE ROLE IF NOT EXISTS migration_admin WITH
  NOINHERIT NOCREATEROLE NOCREATEDB NOLOGIN;

GRANT USAGE ON SCHEMA public TO migration_admin;
GRANT CREATE ON SCHEMA public TO migration_admin;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO migration_admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO migration_admin;

ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO migration_admin;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO migration_admin;

-- Application User Role (Runtime)
CREATE ROLE IF NOT EXISTS app_user WITH
  NOINHERIT NOCREATEROLE NOCREATEDB NOLOGIN;

GRANT USAGE ON SCHEMA public TO app_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_user;

ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO app_user;

-- Grant roles to UAMIs
GRANT migration_admin TO "UAMI-testAC";
GRANT app_user TO "UAMI-appProd";

-- Verification
SELECT 'PostgreSQL roles setup completed successfully' AS status;
```

### Bash Script for Automation

Create `scripts/init-postgres-roles.sh`:

```bash
#!/bin/bash
set -euo pipefail

# PostgreSQL Role Initialization Script
# This script sets up roles and permissions for CI/CD and runtime access

PGHOST="${PGHOST:-}"
PGDATABASE="${PGDATABASE:-}"
PGUSER="${PGUSER:-postgres}"

# Validation
if [[ -z "$PGHOST" ]] || [[ -z "$PGDATABASE" ]]; then
  echo "❌ Error: PGHOST and PGDATABASE environment variables must be set"
  exit 1
fi

echo "🔧 Setting up PostgreSQL roles for AKS Demo..."
echo "   Database: $PGDATABASE"
echo "   Host: $PGHOST"

# Execute the SQL setup
psql -h "$PGHOST" \
     -U "$PGUSER" \
     -d "$PGDATABASE" \
     -v ON_ERROR_STOP=1 \
     -f scripts/setup-postgres-roles.sql

echo "✅ PostgreSQL roles configured successfully"
echo ""
echo "Roles created:"
echo "  • migration_admin (for GitHub Actions migrations)"
echo "  • app_user (for AKS runtime application)"
echo ""
echo "UAMIs assigned:"
echo "  • UAMI-testAC → migration_admin"
echo "  • UAMI-appProd → app_user"
```

### Integration with Infrastructure as Code

In your Terraform/ARM template:

```hcl
# Example: Terraform
resource "null_resource" "postgres_setup" {
  provisioner "local-exec" {
    command = "bash scripts/init-postgres-roles.sh"
    environment = {
      PGHOST     = azurerm_postgresql_server.main.fqdn
      PGDATABASE = azurerm_postgresql_database.project_db.name
      PGUSER     = "postgres"
    }
  }

  depends_on = [
    azurerm_postgresql_server.main,
    azurerm_postgresql_database.project_db,
  ]
}
```

---

## Security Checklist

- [ ] Roles created with `NOLOGIN` (cannot log in directly)
- [ ] `migration_admin` has no `CREATEROLE` or `CREATEDB` permissions
- [ ] `app_user` has DML-only permissions (no DDL)
- [ ] Both UAMIs assigned to appropriate roles
- [ ] Network security group restricts database access to authorized IPs
- [ ] Audit logging enabled for role changes
- [ ] Database backups taken after role setup
- [ ] Documented in your security/operations runbook

---

## Reference

- [PostgreSQL Role Concepts](https://www.postgresql.org/docs/current/user-manag.html)
- [Default Privileges](https://www.postgresql.org/docs/current/ddl-priv.html)
- [Azure PostgreSQL with Entra ID](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/how-to-configure-sign-in-azure-ad-authentication)
- [AKS Workload Identity](https://learn.microsoft.com/en-us/azure/aks/workload-identity-overview)

