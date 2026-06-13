# Production data source (Render Postgres)

The live app reads and writes **Render Postgres** (`harisree-db`), not Supabase.

| Layer | Host / ID |
|-------|-----------|
| Flutter web (Vercel) | `API_BASE_URL` → `https://my-purchases-api.onrender.com` |
| API (`my-purchases-api`) | `DATABASE_URL` → internal `dpg-d8fu1p77f7vs73eooiu0-a/harisree_db` |
| Local `pg_dump` / Alembic | Render **external** URL from Dashboard → Connect |

Verify anytime:

```http
GET https://my-purchases-api.onrender.com/health/ready
```

Expect `"db":"ok"` and `alembic_version` at head (`062_trade_report_indexes` as of 2026-06-06).

Also expect `expected_alembic_head: 062_trade_report_indexes`, `schema_ok: true`, and `stock_sync_ready: true`.

**Important:** Production migrations must run against **Render Postgres** (`harisree-db`), not the Supabase MCP project. Prefer Render pre-deploy `alembic upgrade head` (see [`render-service-sync.ps1`](../scripts/render-service-sync.ps1)); if preDeploy is missing on the live service, apply via `backend/scripts/apply_render_upgrade_062.py` (or `061` for prior head) or Render Shell + `RENDER_DB_EXTERNAL_URL` locally.

After deploy, hard-refresh the PWA (Ctrl+Shift+R) so the browser does not use a cached `main.dart.js`.
