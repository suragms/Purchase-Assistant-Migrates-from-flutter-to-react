# SQL scripts archive (`backend/sql/`)

**Status:** Archive / ops reference — **not** the primary production migration path.

## Production migration path

- **Alembic only** for Render Postgres (`backend/alembic/versions/`).
- One-off Render hotfixes live under `backend/scripts/ops/` (e.g. token_version column).

## `backend/sql/*.sql` (59 files)

Numbered scripts (`001_*.sql` … `067_*.sql`) were used during early development and Render parity patches (`034b_*`, `035b_*`, etc.).

| Use | Do |
|-----|-----|
| New schema change | Add Alembic revision; do **not** add a parallel numbered SQL unless ops-only |
| Local SQLite dev | `sqlite_bootstrap` + Alembic |
| Render prod drift | Compare `pg_dump --schema-only` vs Alembic head (see `DB_RECONCILE.md`) |
| Historical reference | Keep files; mark deprecated in commit messages when superseded |

## Do not delete

Until Alembic chain matches production snapshot, keep numbered SQL for forensic diff. Phase 4 rule: **no blind drops**.

## Related

- `backend/sql/MIGRATION_INDEX.md` — index if present
- `docs/cleanup/DB_RECONCILE.md` — Render vs repo reconciliation steps
