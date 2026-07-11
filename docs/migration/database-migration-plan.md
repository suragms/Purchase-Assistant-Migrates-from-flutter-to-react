# Database Migration Plan — Purchase Assistant

## Migration Goal

Migrate from the existing FastAPI + SQLAlchemy + Alembic stack (PostgreSQL) to the new ASP.NET Core 10 + EF Core stack while preserving:
- **Zero data loss** — every row survives the cutover
- **Zero schema drift** — the EF Core schema matches the PostgreSQL truth exactly
- **Zero downtime** — old and new stack run side-by-side against the same database during cutover

---

## Table of Contents

1. [Current Architecture](#1-current-architecture)
2. [Target Architecture](#2-target-architecture)
3. [Schema Inventory](#3-schema-inventory)
4. [Delta Analysis: Models vs SQL Files vs Domain Entities](#4-delta-analysis)
5. [Migration Strategy: Side-by-Side \[Phase 1\]](#5-migration-strategy-side-by-side)
6. [New-Schema-Only \[Phase 2\]](#6-migration-strategy-new-schema-only)
7. [EF Core Snapshot Workflow](#7-ef-core-snapshot-workflow)
8. [Row-Level Security Compatibility](#8-row-level-security-compatibility)
9. [Data Backfill & Data-Only Migrations](#9-data-backfill--data-only-migrations)
10. [Cutover Checklist](#10-cutover-checklist)
11. [Rollback Plan](#11-rollback-plan)
12. [Risk Register](#12-risk-register)

---

## 1. Current Architecture

| Aspect | Current (FastAPI) |
|--------|-------------------|
| **Runtime** | Python 3.11+ / FastAPI |
| **ORM** | SQLAlchemy 2.x (async) |
| **Migrations** | Alembic (65 revision files in `backend/alembic/versions/`) |
| **Schema bootstrap** | `Base.metadata.create_all()` + Alembic chain (001→068) |
| **Idempotent SQL** | 62 files in `backend/sql/` (numbered + supplemental) |
| **DB** | PostgreSQL 15+ (Render / Supabase) |
| **Compat shims** | `db_schema_compat.py` — runtime introspection for optional columns |
| **RLS** | Migration 054: `p_business_isolation` policy on all `business_id` tables |
| **CI** | SQLite via `HEXA_USE_SQLITE` env var |

### Migration Chain (Alembic)

```
001 (bootstrap create_all)
→ 002 (line_kg)
→ 003 (contact_email)
→ 005 (item_code)
→ 007 (ssot_fks)
→ 008 (tp_profit)
→ 009 (decimal_precision)
→ 010 (tp_line_decimals)
→ 011 (tp_line_unit_type)
→ 012 (dashboard_indexes)
→ 013 (line_indexes)
→ 014 (broker_deal_defaults)
→ 015 (commission_mode)
→ 016 (catalog_snapshot)
→ 017 (broker_image_url)
→ 018 (purchase_scan_traces)
→ 019 (smart_unit_intelligence)
→ 020 (home_reports_indexes)
→ 021 (tp_delivery)
→ 022 (list_status_date)
→ 023 (catalog_active_partial)
→ 024 (harisree_sql_parity)
→ 025 (user_system_rebuild)
→ [026–027 absent in git]
→ 028 (user_mgmt_v2)
→ 029 (stockease_operations)
→ 030 (catalog_barcode)
→ 031 (stock_audit_business)
→ 032 (staff_activity_action_types)
→ 033 (catalog_public_qr)
→ 034 (stock_physical_counts)
→ 035 (opening_stock)
→ 036 (staff_purchase_logs)
→ 037 (stock_movements)
→ 038 (notification_alert_v2)
→ 039 (stock_dispute_cases)
→ 040 (purchase_delivery_tracking)
→ 041 (purchase_delivery_extras)
→ 042 (catalog_stock_list_sort_index)
→ 043 (audit_perf_indexes)
→ 044 (catalog_current_stock_non_negative)
→ 045 (purchase_delete_integrity)
→ 046 (report_saved_views)
→ 047 (purchase_line_received_qty)
→ 048 (stock_commit_backfill_guards)
→ 049 (stock_ledger_sql_backfill)
→ 050 (stock_ledger_replay_current_stock)
→ 051 (delivery_discrepancy_and_lifecycle)
→ 052 (stock_movement_unit_mismatch_flag)
→ 053 (purchase_lifecycle_statuses)
→ 054 (enable_rls_business_policies)
→ 055 (business_whatsapp_contact)
→ 056 (purchase_damage_reports)
→ 057 (purchase_damage_reports_v2)
→ 058 (barcode_lookup_indexes)
→ 059 (staff_activity_action_types_v2)
→ 060 (stock_list_performance_indexes)
→ 061 (catalog_unit_simplify)
→ 062 (trade_report_indexes)
→ 063 (pg_hot_path_indexes)
→ 064 (critical_performance_indexes)
→ 065 (archive_legacy_entries_tables)
→ 066 (drop_scan_and_whatsapp)
→ 067 (user_token_version)
→ 068 (physical_count_idempotency_key) ← head
```

**NOTE:** Revisions 026 and 027 are missing from git. The SQL files `026_stock_audits.sql` and `027_user_system_rebuild.sql` exist but do not have corresponding Alembic revision files. Do not renumber production revisions.

---

## 2. Target Architecture

| Aspect | Target (ASP.NET Core) |
|--------|----------------------|
| **Runtime** | .NET 10 / ASP.NET Core |
| **ORM** | EF Core 10 (Npgsql provider) |
| **Migrations** | EF Core migrations (`dotnet ef migrations add`) |
| **Schema bootstrap** | `context.Database.MigrateAsync()` on startup |
| **CI** | Local DB or testcontainers (PostgreSQL) |
| **RLS** | Disabled in .NET stack (app-level authorization instead) |

### Side-by-side Deployment Topology [Phase 1]

```
┌──────────────┐     ┌──────────────┐
│  FastAPI     │     │  ASP.NET     │  ← both read/write same DB
│  (old)       │     │  (new)       │
└──────┬───────┘     └──────┬───────┘
       │                    │
       └─────────┬──────────┘
                 ▼
       ┌──────────────────┐
       │  PostgreSQL      │
       │  (existing DB)   │
       └──────────────────┘
```

---

## 3. Schema Inventory

### 3.1 Tables (44 total across both stacks)

All tables present in both the SQLAlchemy models and the EF Core domain entities:

| # | Table | Created In | Notes |
|---|-------|-----------|-------|
| 1 | `businesses` | 001 | bootstrap |
| 2 | `users` | 001 | bootstrap |
| 3 | `memberships` | 001 | bootstrap |
| 4 | `password_reset_tokens` | 001 | bootstrap |
| 5 | `item_categories` | 001 | bootstrap |
| 6 | `category_types` | 001 | bootstrap |
| 7 | `catalog_items` | 001 | 65+ columns, most-complex table |
| 8 | `catalog_variants` | 001 | bootstrap |
| 9 | `catalog_item_default_suppliers` | 001 | bootstrap |
| 10 | `catalog_item_default_brokers` | 001 | bootstrap |
| 11 | `supplier_item_defaults` | 001 | bootstrap |
| 12 | `suppliers` | 001 | bootstrap |
| 13 | `brokers` | 001 | bootstrap |
| 14 | `broker_supplier_m2m` | 001 | bootstrap (`broker_supplier_m2m`, not `broker_supplier_links`) |
| 15 | `trade_purchases` | 001 | 40+ columns |
| 16 | `trade_purchase_lines` | 001 | 40+ columns |
| 17 | `trade_purchase_drafts` | 001 | bootstrap |
| 18 | `master_units` | 019 | smart unit intelligence |
| 19 | `item_packaging_profiles` | 019 | |
| 20 | `ocr_item_aliases` | 019 | |
| 21 | `smart_unit_rules` | 019 | |
| 22 | `item_learning_history` | 019 | |
| 23 | `unit_confidence_logs` | 019 | |
| 24 | `ai_item_profiles` | 019 | |
| 25 | `smart_package_rules` | 019 | |
| 26 | `stock_adjustment_log` | 021 | |
| 27 | `user_sessions` | 022 | |
| 28 | `staff_activity_log` | 022 | |
| 29 | `notifications` | 023 | |
| 30 | `reorder_list` | 025 | |
| 31 | `stock_audits` | 026 | |
| 32 | `stock_audit_items` | 026 | |
| 33 | `daily_usage_logs` | 029 | |
| 34 | `staff_checklist_templates` | 029 | |
| 35 | `staff_checklist_completions` | 029 | |
| 36 | `stock_physical_counts` | 034 | |
| 37 | `staff_purchase_logs` | 036 | |
| 38 | `stock_movements` | 037 | |
| 39 | `stock_dispute_cases` | 039 | |
| 40 | `report_saved_views` | 046 | |
| 41 | `purchase_lifecycle_events` | 051 | |
| 42 | `delivery_discrepancies` | 051 | **No SQLAlchemy model** — exists only as SQL DDL |
| 43 | `purchase_damage_reports` | 056 | |
| 44 | `admin_audit_logs` | bootstrap | |
| 45 | `api_usage_logs` | bootstrap | |
| 46 | `webhook_event_logs` | bootstrap | |

### 3.2 Tables Present in SQL Only (not in current models)

| Table | Created In | SQLAlchemy Model? | EF Core Model? | Action |
|-------|-----------|-------------------|----------------|--------|
| `delivery_discrepancies` | 051 | ❌ | ❌ | Add entity in Phase 2 |
| `_archived_entries` | 065 | ❌ | ❌ | Skip (legacy data, no app code) |
| `_archived_entry_line_items` | 065 | ❌ | ❌ | Skip (legacy data, no app code) |

### 3.3 Tables Dropped in Migration 066

| Table | Dropped In | EF Core Status |
|-------|-----------|----------------|
| `purchase_scan_traces` | 066 | Not modeled |
| `catalog_aliases` | 066 | Not modeled |
| `entries` (renamed → `_archived_entries`) | 065 | Not modeled |
| `entry_line_items` (renamed → `_archived_entry_line_items`) | 065 | Not modeled |

These tables do not appear in current production and must NOT be included in EF Core migration.

### 3.4 View-Only / Supabase Tables (not in current models)

| Table | Created In | Notes |
|-------|-----------|-------|
| `app_notifications` | Optional / legacy | Referenced in `063_pg_hot_path_indexes.sql` only. Not in current models. |
| `stock_adjustment_logs` (plural) | Optional / legacy | Referenced in `063_pg_hot_path_indexes.sql` only. Not in current models. |

These are legacy table names that may or may not exist on a given instance. EF Core models target the canonical names (`notifications`, `stock_adjustment_log`).

---

## 4. Delta Analysis

### 4.1 Type Mapping

| PostgreSQL | SQLAlchemy | EF Core (Npgsql) | Notes |
|-----------|-----------|------------------|-------|
| `UUID` | `Uuid(as_uuid=True)` | `Guid` / `NpgsqlPropertyBuilderContext.HasColumnType("uuid")` | Default PK type |
| `TIMESTAMPTZ` | `DateTime(timezone=True)` | `DateTime` + `Kind=Utc` / `HasColumnType("timestamptz")` | Must preserve timezone |
| `NUMERIC(p,s)` | `Numeric(p,s)` | `decimal` + `HasPrecision(p,s)` | All decimal types must match |
| `JSONB` | `JSON().with_variant(JSONB, "postgresql")` | `Jsonb` / `HasColumnType("jsonb")` | Use Npgsql JSON extension |
| `JSON` | `JSON` | `HasColumnType("json")` | Use for non-jsonb columns |
| `VARCHAR(n)` | `String(n)` | `HasMaxLength(n)` / `HasColumnType("varchar(n)")` |
| `BOOLEAN` | `Boolean` | `bool` |
| `INTEGER` | `Integer` | `int` |

### 4.2 Index Delta

Every index created in migrations 001-068 must be present in the EF Core model. The EF Core DbContext must define indexes via `HasIndex()` calls or data annotations.

**Total indexes:** ~70+ across all tables. Every SQL `CREATE INDEX` statement has a corresponding fluent API call in `PurchaseAssistantDbContext`.

### 4.3 Constraint Delta

| Constraint | SQL Source | EF Core Implementation |
|-----------|-----------|----------------------|
| `CHECK (current_stock >= 0)` | 044 | `HasCheckConstraint("chk_current_stock_non_negative", ...)` |
| `CHECK (delivery_status IN (...))` | 040 | Enum / check constraint |
| `CHECK (status IN (...))` | 053 | 20-value lifecycle check |
| `CHECK (action_type IN (...))` | 059 | Enum / check constraint (33 values) |
| `UNIQUE (business_id, human_id)` | 001 | `HasAlternateKey()` |
| `UNIQUE (business_id, idempotency_key)` | 037 | `HasIndex().IsUnique()` |
| Partial unique indexes | 025, 034, 068 | `HasFilter()` in EF Core |

### 4.4 Compatibility Shim: `catalog_items.type_id`

The `db_schema_compat.py` file handles the case where `type_id` column on `catalog_items` may not exist on older database instances. This was added in migration 027 (`user_system_rebuild.sql`).

**EF Core handling:** The `type_id` property on `CatalogItem` entity must be nullable (`Guid?`). The initial EF Core migration will create it as nullable. If the column already exists, the migration will be a no-op on existing tables (but will create it on new tables).

### 4.5 Default Value Delta

Many columns use `DEFAULT` values in SQL. EF Core must replicate these:

| Column | SQL Default | EF Core |
|--------|------------|---------|
| `current_stock` | `NUMERIC(12,3) DEFAULT 0` | `HasDefaultValue(0)` |
| `stock_version` | `INTEGER DEFAULT 0` | `HasDefaultValue(0)` |
| `token_version` | `INTEGER DEFAULT 0` | `HasDefaultValue(0)` (with `ValueGeneratedOnAdd()`) |
| `public_token` | Auto-generated md5 hash | Client-side in C#, `HasDefaultValueSql("gen_random_uuid()")` |
| `delivery_status` | `VARCHAR(30) DEFAULT 'pending'` | `HasDefaultValue("pending")` |
| `status` variants | Various | `HasDefaultValue("confirmed")` or enum default |
| `created_at` | `DEFAULT now()` | `HasDefaultValueSql("now()")` |

---

## 5. Migration Strategy: Side-by-Side [Phase 1]

### 5.1 Principle

The old FastAPI stack and new ASP.NET Core stack run **concurrently** against the **same PostgreSQL database**. Both stacks can read and write all tables. This allows gradual endpoint migration with instant rollback.

### 5.2 Schema Ownership

| Stack | Creates Tables? | Manages Migrations? |
|-------|----------------|---------------------|
| FastAPI + Alembic | ✅ (existing) | ✅ (Alembic 001→068) |
| ASP.NET Core + EF Core | ❌ (Phase 1) | ❌ (Phase 1) |

In Phase 1, EF Core runs **without** database initialization (`EnsureCreated` / `Migrate` disabled). The schema is already managed by Alembic.

### 5.3 EF Core Configuration for Phase 1

```csharp
// In Program.cs — Phase 1: don't touch the database schema
// Commented out: await context.Database.MigrateAsync();
```

```csharp
// DbContext configuration
protected override void OnModelCreating(ModelBuilder modelBuilder)
{
    // All schema configuration matches existing PostgreSQL schema.
    // ToTable() / HasColumnName() / HasColumnType() map exactly to physical schema.
    // Indexes, constraints, defaults all configured via fluent API.
}
```

### 5.4 Required EF Core Mappings for Phase 1

All columns in the EF Core entities must match physical column names exactly. Use `[Column("snake_case_name")]` or `HasColumnName()` for every column that diverges from C# PascalCase.

### 5.5 Sequence Readiness (Phase 1)

The following DB features from the existing schema must be accounted for in EF Core reads:
- **RLS policies** (migration 054): EF Core queries must include business_id filters explicitly (app-level authorization). The `app.current_business_id` session variable is not set by .NET.
- **CHECK constraints**: EF Core won't validate these; throw on write if violated.
- **Triggers**: Any triggers on tables must be understood; EF Core bypasses triggers if using bulk operations.

---

## 6. New-Schema-Only [Phase 2]

Once all endpoints have been migrated and FastAPI is decommissioned:

### 6.1 EF Core Migration Initialization

```bash
dotnet ef migrations add InitialCreate --project backend-dotnet/src/Infrastructure
```

This generates a migration that creates all 44+ tables from scratch. The migration is used for:
- Local development / CI
- Future schema changes

### 6.2 Production Schema Handover

1. Run `dotnet ef migrations script` to generate raw SQL
2. Compare output with `backend/sql/MIGRATION_INDEX.md` to verify no drift
3. Apply `alembic downgrade base` to remove Alembic tracking, OR leave `alembic_version` table in place (zero impact)
4. Enable `context.Database.MigrateAsync()` in `Program.cs`

### 6.3 RLS Removal

RLS policies (migration 054) must be explicitly dropped in an EF Core migration when the .NET stack takes over:

```sql
DROP POLICY IF EXISTS p_business_isolation ON <table>;
ALTER TABLE <table> DISABLE ROW LEVEL SECURITY;
```

This is handled by app-level authorization in ASP.NET Core.

### 6.4 Tables Not Modeled in EF Core

| Table | Reason | Action in Phase 2 |
|-------|--------|-------------------|
| `alembic_version` | Alembic internal tracking | Leave in place; ignored by EF |
| `_archived_entries` | Legacy data, no app code | Leave in place |
| `_archived_entry_line_items` | Legacy data, no app code | Leave in place |
| `delivery_discrepancies` | No model yet | Add entity before Phase 2 cutover |

---

## 7. EF Core Snapshot Workflow

Initial EF Core migration snapshot is in `backend-dotnet/src/Infrastructure/Migrations/`. It is the canonical EF Core view of the schema.

### 7.1 Adding New Migrations

```bash
cd backend-dotnet/src/Infrastructure
dotnet ef migrations add <Description> \
  --startup-project ../Api/PurchaseAssistant.Api.csproj
```

### 7.2 Generating SQL Scripts

```bash
dotnet ef migrations script \
  --output ../../sql/ef-core-migration.sql \
  --idempotent
```

### 7.3 CI Strategy

CI runs `dotnet ef database update` against a test PostgreSQL instance (via Testcontainers or ephemeral Render DB).

---

## 8. Row-Level Security Compatibility

### 8.1 Current RLS Setup (Migration 054)

Migration `054_enable_rls_business_policies.sql` applies to every table with a `business_id` column:
- `ALTER TABLE <table> ENABLE ROW LEVEL SECURITY`
- `CREATE POLICY p_business_isolation USING (business_id = current_setting('app.current_business_id')::UUID)`

### 8.2 Impact on .NET

The .NET stack does **not** set `app.current_business_id` as a PostgreSQL session variable. Therefore:
- **Reads**: .NET queries will see only rows matching the session variable IF RLS is still enabled. If the .NET app doesn't set it, queries will return **zero rows** for RLS-enabled tables.
- **Writes**: RLS `WITH CHECK` will reject inserts/updates that don't match the session variable.

### 8.3 Solution

**Phase 1**: The .NET app does `SET app.current_business_id = '<guid>'` on each connection via `DbCommandInterceptor` or `connection.Open()` event.

```csharp
public class RlsInterceptor : DbCommandInterceptor
{
    public override async ValueTask<InterceptionResult<DbDataReader>> ReaderExecutingAsync(
        DbCommand command, CommandEventData eventData, InterceptionResult<DbDataReader> result,
        CancellationToken ct = default)
    {
        await command.Connection?.ExecuteSqlRawAsync(
            $"SET app.current_business_id = '{GetBusinessId()}'", ct)!;
        return result;
    }
}
```

**Approach**: Use `NpgsqlConnection.GlobalTypeMapper` or a connection interceptor to set the session variable at connection open. This avoids modifying every query.

### 8.4 RLS Table Inventory

Tables with RLS enabled (from migration 054):
`catalog_items`, `item_categories`, `category_types`, `suppliers`, `brokers`, `broker_supplier_m2m`, `trade_purchases`, `trade_purchase_lines`, `trade_purchase_drafts`, `stock_adjustment_log`, `stock_movements`, `stock_physical_counts`, `stock_audits`, `stock_audit_items`, `stock_dispute_cases`, `daily_usage_logs`, `staff_checklist_templates`, `staff_checklist_completions`, `staff_purchase_logs`, `notifications`, `report_saved_views`, `reorder_list`

Additionally, `stock_physical_counts` has RLS enabled via migration 034.

---

## 9. Data Backfill & Data-Only Migrations

Several SQL files are **data-only** (no schema changes). These must be replicated in .NET:

| SQL File | Purpose | .NET Equivalent |
|----------|---------|-----------------|
| `030_catalog_barcode.sql` | Backfill numeric item_code → barcode | Seed migration or startup logic |
| `033_catalog_public_qr.sql` | Generate md5 public_token | Client-side GUID generation |
| `045_purchase_delete_integrity.sql` | Repair delivery_status + catalog snapshots | Not needed (data repair) |
| `051_delivery_discrepancy_and_lifecycle.sql` | Reconcile current_stock from opening_stock + movements | Seed migration |
| `061_catalog_unit_simplify.sql` | Normalize 5-unit profiles | Seed migration |
| `box_default_items_per_box_backfill.sql` | Set default_items_per_box = 1 for box items | Seed migration |
| `production_unit_metadata_update.sql` | Canonical unit metadata from Excel | Seed migration |
| `_019_compact.sql` / `supabase_019*` | Insert master_units seed data | Seed migration |
| `033b_trade_line_qty_in_stock_unit.sql` | Requires `scripts/backfill_line_stock_unit_qty.py` | Not needed (computed at write time) |

### 9.1 Seed Data in EF Core

Data-only SQL is converted to EF Core seed data in `PurchaseAssistantDbContext.OnModelCreating` via `.HasData()`:

```csharp
modelBuilder.Entity<MasterUnit>().HasData(
    new MasterUnit { UnitCode = "BAG", DisplayName = "Bag", Category = "count" },
    new MasterUnit { UnitCode = "KG", DisplayName = "Kilogram", Category = "weight" },
    // ... 13 more
);
```

---

## 10. Cutover Checklist

### Pre-Cutover (Phase 1 — Side-by-Side)

- [ ] Verify all 44+ EF Core entity classes match SQLAlchemy models column-for-column
- [ ] Verify all `NUMERIC(p,s)` types match precision/scale
- [ ] Verify all index names and definitions match
- [ ] Verify all constraint definitions match
- [ ] Implement RLS session variable interceptor in .NET
- [ ] Deploy new .NET stack read-only (read endpoints only)
- [ ] Run read-query parity tests between FastAPI and .NET responses
- [ ] Enable write endpoints on .NET, monitor write errors
- [ ] Add `delivery_discrepancies` entity to EF Core (missing from model)

### Cutover (Phase 2 — .NET Only)

- [ ] Run `dotnet ef migrations script --idempotent` and review against existing schema
- [ ] Back up database (pg_dump)
- [ ] Run script on a staging/read-replica first to verify zero drift
- [ ] Drop RLS policies via EF Core migration
- [ ] Enable `context.Database.MigrateAsync()` in .NET
- [ ] Remove Alembic `alembic_version` table
- [ ] Deploy final .NET stack
- [ ] Monitor error logs for constraint violations

### Post-Cutover

- [ ] Run data validation queries (row counts per table)
- [ ] Clean up unused SQL files and Alembic directory
- [ ] Remove `db_schema_compat.py` (no longer needed)
- [ ] Archive `backend/sql/` directory
- [ ] Remove `backend/alembic/` directory (or leave as read-only reference)

---

## 11. Rollback Plan

### Phase 1 Rollback (Side-by-Side)

If the .NET stack causes schema damage:
1. Stop .NET deployments
2. FastAPI continues to work (it reads/writes same DB)
3. Restore any modified rows from pg_dump backup
4. No schema changes were made (EF Core migrations disabled)

### Phase 2 Rollback (New Schema)

If schema drift is detected:
1. Run `scripts/restore_from_backup.sh` using the pg_dump taken before cutover
2. Reinstate `alembic upgrade head` to restore migration tracking
3. Re-deploy FastAPI stack
4. Investigate and fix drift before retrying

---

## 12. Risk Register

| Risk | Impact | Mitigation |
|------|--------|------------|
| Column type mismatch (NUMERIC precision) | Constraint violation on write | Test each table's data types against existing schema with a parity tool |
| RLS blocks .NET reads | Empty query results | Implement `app.current_business_id` interceptor before Phase 1 read path |
| Missing index | Query performance degradation | Verify all indexes in `sql/` against EF Core `HasIndex()` configuration |
| Missing `delivery_discrepancies` entity | 501 errors on delivery endpoints | Add entity to Domain project before Phase 1 completion |
| CHECK constraint mismatch | Write errors | Review all CHECK constraints (status, action_type, delivery_status) against `sql/` definitions |
| `token_version` `server_default` mismatch | JWT invalidation logic broken | Verify `HasDefaultValueSql("0")` or `HasDefaultValue(0)` + `ValueGeneratedNever()` |
| Legacy JSONB columns with different casing in PG vs EF Core | Deserialization failure | Add `[Column("snake_case_name")]` to every JSONB property |
| Alembic vs EF Core migration ordering conflict | Race condition on DDL | Disable EF Core migrations in Phase 1; Alembic owns DDL |
| `_019_compact.sql` vs `supabase_019_smart_unit_intelligence.sql` duplication | Duplicate seed data | Use `.HasData()` in EF Core; SQL files are one-time run |

---

## Appendix A: SQL Supplement Classification

| Classification | Files | Action |
|---------------|-------|--------|
| **Alembic twins** | 029–068 (matching rev numbers) | Indexes/constraints → EF Core fluent API |
| **Supplemental** | `033b_*`, `034b_*`, `035b_*` | Data backfill → .NET startup logic or seed |
| **Supabase-only** | `supabase_019_*`, `supabase_020_*`, `supabase_061_*` | Not needed (one-time SQL) |
| **Optional** | `optional_pg_trgm_indexes.sql`, `suggested_*`, `index_*` | Performance tuning; evaluate separately |
| **Archived** | `065_archive_legacy_entries_tables.sql` | Skip (data already archived) |
| **Cleanup** | `066_drop_scan_and_whatsapp.sql` | Already applied; do not model dropped tables |

## Appendix B: Entity Status

| Entity | Domain Model | DbContext Config | Controller |
|--------|-------------|------------------|------------|
| Business | ✅ | ✅ | ✅ |
| User | ✅ | ✅ | ✅ |
| Membership | ✅ | ✅ | ✅ |
| PasswordResetToken | ✅ | ✅ | (auth) |
| ItemCategory | ✅ | ✅ | ✅ |
| CategoryType | ✅ | ✅ | (via Catalog) |
| CatalogItem | ✅ | ✅ | ✅ |
| CatalogVariant | ✅ | ✅ | (via Catalog) |
| CatalogItemDefaultSupplier | ✅ | ✅ | (via Catalog) |
| CatalogItemDefaultBroker | ✅ | ✅ | (via Catalog) |
| SupplierItemDefault | ✅ | ✅ | (via Catalog) |
| Supplier | ✅ | ✅ | ✅ |
| Broker | ✅ | ✅ | ✅ |
| BrokerSupplierLink | ✅ | ✅ | (via Contacts) |
| TradePurchase | ✅ | ✅ | ✅ |
| TradePurchaseLine | ✅ | ✅ | (via Purchase) |
| TradePurchaseDraft | ✅ | ✅ | (via Purchase) |
| MasterUnit | ✅ | ✅ | (unit intelligence) |
| ItemPackagingProfile | ✅ | ✅ | (unit intelligence) |
| OcrItemAlias | ✅ | ✅ | (unit intelligence) |
| SmartUnitRule | ✅ | ✅ | (unit intelligence) |
| ItemLearningHistory | ✅ | ✅ | (unit intelligence) |
| UnitConfidenceLog | ✅ | ✅ | (unit intelligence) |
| AiItemProfile | ✅ | ✅ | (unit intelligence) |
| SmartPackageRule | ✅ | ✅ | (unit intelligence) |
| StockAdjustmentLog | ✅ | ✅ | ✅ |
| UserSession | ✅ | ✅ | (auth) |
| StaffActivityLog | ✅ | ✅ | ✅ |
| AppNotification | ✅ | ✅ | ✅ |
| ReorderListEntry | ✅ | ✅ | ✅ |
| StockAudit | ✅ | ✅ | ✅ |
| StockAuditItem | ✅ | ✅ | (via Stock Audits) |
| DailyUsageLog | ✅ | ✅ | ✅ |
| StaffChecklistTemplate | ✅ | ✅ | (via Operations) |
| StaffChecklistCompletion | ✅ | ✅ | (via Operations) |
| StockPhysicalCount | ✅ | ✅ | ✅ |
| StaffPurchaseLog | ✅ | ✅ | ✅ |
| StockMovement | ✅ | ✅ | ✅ |
| StockDisputeCase | ✅ | ✅ | ✅ |
| ReportSavedView | ✅ | ✅ | ✅ |
| PurchaseLifecycleEvent | ✅ | ✅ | (via Purchase) |
| **DeliveryDiscrepancy** | ❌ | ❌ | ❌ |
| PurchaseDamageReport | ✅ | ✅ | ✅ |
| AdminAuditLog | ✅ | ✅ | (admin) |
| ApiUsageLog | ✅ | ✅ | (admin) |
| WebhookEventLog | ✅ | ✅ | (admin) |
| BusinessGoal | ✅ | ✅ | ✅ |
