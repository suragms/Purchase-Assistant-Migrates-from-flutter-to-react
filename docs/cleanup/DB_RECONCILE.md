# Database reconciliation — Render Postgres vs Alembic

**Production:** Render Postgres 1GB (not Supabase for live API).  
**Goal:** Single migration truth via Alembic; read-only index review before any drops.

## 1. Schema snapshot (ops)

From a machine with Render DB access:

```bash
pg_dump "$DATABASE_URL" --schema-only --no-owner --no-privileges > /tmp/render_schema.sql
```

Compare tables/columns/indexes to Alembic head in repo (`backend/alembic/versions/`).

Known drift examples (2026-06):

| Item | Notes |
|------|--------|
| `users.token_version` | Added via `backend/scripts/ops/apply_render_hotfix_067_token_version.py` when prod lagged Alembic |
| Head naming | Prod may report `065_api_storm_hotpath_indexes`; repo chain may use `065_archive_legacy_entries_tables` → `067_user_token_version` |

**Do not** drop indexes from migrations `060`/`064`/`065` without `EXPLAIN ANALYZE` on:

- Purchase list (`trade_purchases` + lines)
- Stock list / low-stock
- Home overview bundle queries

## 2. Alembic as SSOT

```bash
cd backend
alembic current    # on Render shell / CI with DATABASE_URL
alembic heads      # repo expected head
```

Apply pending revisions only after diff review. Prefer Alembic over ad-hoc SQL on prod.

## 3. Index review (read-only)

Run on staging or prod read replica:

```sql
EXPLAIN ANALYZE
SELECT ... -- representative home-overview / trade-items / stock list queries
```

Document duplicate indexes before proposing a drop migration.

## 4. Files

| Path | Role |
|------|------|
| `backend/alembic/` | **Authoritative** schema evolution |
| `backend/sql/` | **Archive** — see `SQL_ARCHIVE.md` |
| `backend/scripts/ops/` | One-off Render upgrades / hotfixes |

## 5. Out of scope (this doc)

- Automatic index drops without EXPLAIN proof
- Deleting Alembic history or `backend/sql/` wholesale
