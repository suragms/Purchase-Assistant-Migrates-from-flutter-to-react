# Purchase Assistant — Living task board

**Last updated:** 2026-05-21 (user/staff system rebuild)
**App:** `hexa_purchase_assistant` (Flutter + FastAPI + Supabase)  
**Product docs:** `docs/harisree/` (`MASTER_REFERENCE.md`, `FEATURES_DEEP_PLAN.md`)

---

## Master plan status (May 2026)

| Section | Status |
|---------|--------|
| 0 Repo cleanup | Done — `TASKS.md` only at root (+ `README.md`); junk MD gitignored |
| 1 Critical bugs BUG-01–14 | Done |
| 2 UI/UX 2.1–2.7 | Done |
| 3 Features 3.1–3.4 | Done |
| 4 Page audit | Done (see snapshot below) |
| 5 Cursor rules | Done — `.cursor/rules/purchase-assistant-master.mdc` |
| 6 Smart defaults | Done |
| 7 Device testing | Manual — checklist below |

**Code plan:** closed. Remaining work is **device QA** (Section 7) and **deploy** (checklist below).

---

## May 20 screenshot pass (critical fixes + UX)

| ID | Status | Notes |
|----|--------|-------|
| Session 0 | Done | Web item-pick overlay + `StaffActivityLogger` Ref fix |
| FIX-01 | Done | Stock list: removed `Scrollbar` crash |
| FIX-02 | Done | Friendly errors on home stock movement; catalog already had `FriendlyLoadError` |
| FIX-03 | Done | Home throttle 5s; trimmed invalidations; reports inflight 3s cooldown |
| FIX-04 | Done | Reports debug logs + existing empty fallback |
| FIX-05 / UX-02 | Done | Stock filter bottom sheet; 3-col table; active filter pill |
| FIX-06 / UX-01 | Done | Removed home catalog chips; 3-col quick actions; 2x2 stat cards |
| FIX-07 | Code verified | Broker commission UI exists when `brokerId` is set; physical device QA still recommended |
| FIX-08 | Code verified | Suggestion overlays use tap grouping/grace handling; physical iOS/Android QA still recommended |
| FIX-09 | Done | Staff stock update invalidates activity + alert counts |
| FIX-10 | Done | Barcode lookup 10s timeout + friendly slow message |
| FIX-11 | Done | Web: `GET /stock/reorder` before `/{id}` (422 fix); `_HexaErrorBoundary` post-frame `setState`; bulk barcode print `Wrap` chips + PDF download |
| FIX-12 | Done | Bulk print: `bulkStockListProvider` loads all pages (506+); chunked `barcode/batch`; label size Small/Medium/Large |
| UX-03 | Done | Compact 4-col report tabs; ring summary card; PDF actions sheet; `hideTopStatRow` on overview; ~48dp item rows |
| UX-04 | Done | Item detail collapsible sections |
| UX-05 | Done | A4 dense barcode grid (margins/gaps + dynamic cols/rows); `Isolate.run` / web path; bulk dense toggle + progress; `run_web_dev.ps1 -WebPort` |
| UX-06 | Done | Home Today/Month spend cards now show BAGS/BOXES/TINS/KG sublines from dashboard unit totals |
| UX-07 / UX-11 | Done | Purchase item full-page flow aligned with keyboard-resizing scaffold; Save/Add More remains pinned |
| UX-08 | Done | Reports purchase fetch already keyed by business/date range; debug log now prints range + key |
| UX-09 / PERF-02 | Done | Stock header compacted to search + status chips + active filter pill; table stays 3 columns with updated-today marker |
| UX-10 | Done | Barcode print route verified; stock long-press print route now URI-encodes item id |
| UX-12 | Done | Barcode/report/supplier/item/broker/Purchase print-share filenames are descriptive and date-stamped |
| PERF-01 | Done | Purchase item notes no longer trigger live totals rebuilds; full-page preview remains behind `RepaintBoundary` |
| HOME-REBUILD | Done | Owner `/home` dense warehouse dashboard: global period chips, compact header/KPI/quick actions, grouped recent changes, deduped feeds, shell FAB 48dp |
| FIX-13 | Done | Web “Something went wrong” on Stock tab: defer home fetches/polling when IndexedStack branch ≠ Home; inline activity-feed audits; treat stale dashboard/provider errors as non-fatal |
| HOME-PIE-ANALYTICS | Done | Owner `/home`: unified analytics card (inventory summary API + ring + breakdown tabs + ranked list); operational alert banner; collapsible feeds; removed 2×2 KPI strip |
| USER-SYSTEM | Done | Identifier login (username/phone/email); user CRUD + credentials UX; tabbed `UserProfilePage`; permissions_json; server LOGIN/PASSWORD_RESET audit; staff dashboard alias + route guards; Alembic `025_user_system_rebuild` |

---

## Post-master backlog (optional)

| Item | Notes |
|------|--------|
| FCM push | Owner alert when staff saves purchase while app is killed |
| Per-category last supplier | Wire `PurchaseSmartDefaults.loadLastSupplierForCategory` when party step has category context |
| Full `pytest` | Done — `python -m pytest -q` passed 244 tests locally |

**Local verify:** `powershell -File scripts/verify-release.ps1`

---

## Current sprint — critical bugs

| ID | Priority | Status | Summary |
|----|----------|--------|---------|
| BUG-01 | P0 | Done | Stock/shell: `ref.listen` uses post-frame |
| BUG-02 | P0 | Done | Reorder list: `FriendlyLoadError` |
| BUG-03 | P0 | Done | GET 503 retry with backoff |
| BUG-04 | P1 | Done | Stock category chips `Wrap` |
| BUG-05 | P1 | Done | Item sheet catalog loading gate |
| BUG-06 | P1 | Done | Tax Excl/Incl/No GST + preview |
| BUG-07 | P1 | Done | Staff session guards + invalidate |
| BUG-08 | P2 | Done | Reports PDF headers/fields |
| BUG-09 | P2 | Done | Barcode PDF last purchase + bags |
| BUG-10 | P2 | Done | Barcode scan web manual entry |
| BUG-11 | P2 | Done | Suggestion `LayerLink` overlay |
| BUG-12 | P3 | Done | Single primary print CTA |
| BUG-13 | P3 | Done | Cloud sync banner clears on 200 |
| BUG-14 | P3 | Done | Local notifications wired |

---

## Section 3 — Features

| Item | Status | Notes |
|------|--------|-------|
| 3.1 Live data | Done | LIVE pulse; purchase history refresh banner |
| 3.2 Bulk barcode | Done | Multi-select, S/M/L, copies, preview, **2–3 labels per A4 row** |
| 3.3 Staff activity | Done | API log on login/logout/purchase |
| 3.4 Notifications | Done | Purchase, low stock, staff auth, staff purchase (owner bg) |

**Optional later:** FCM when owner app is killed.

---

## Section 6 — Smart defaults

| Item | Status |
|------|--------|
| Last supplier / rate / qty prefs | Done |
| Ranked item search (exact → category → supplier boost) | Done |

---

## Known blockers

| Blocker | Mitigation |
|---------|------------|
| ~~Prod login 503~~ | **Fixed 2026-05-21** — Supabase missing `users.is_active` + `user_sessions` (applied `backend/sql/021–025` via MCP) |
| ~~Prod schema drift~~ | **Fixed 2026-05-21** — Applied `026_stock_audits`, `ocr_correction_events`; Alembic `024_harisree_sql_parity`; audit: `python backend/scripts/schema_audit.py` |
| Render service suspended | Resume `my-purchases-api` in Render dashboard if `/health` returns “Service Suspended” |
| Render MCP workspace not selected | Select the Render workspace in Cursor before env/deploy inspection via MCP |
| Android SDK missing locally | Install/configure Android SDK or set `ANDROID_HOME` before release APK build |
| Flutter test generated asset lock | Retry focused Flutter tests after `build/unit_test_assets` is unlocked/cleaned |
| Local API 503 on stock | `HEXA_USE_SQLITE=1` + `hexa_dev.db` bootstrap |
| Flutter web blank shell | Full restart (not hot reload only) |
| `mobile_scanner` on web | Manual barcode entry |

---

## Deployment checklist

- [x] `pytest` green in `backend/` (`tests/test_health.py` passed; full suite passed 244 tests)
- [x] `flutter analyze` — 0 errors; existing warnings/info remain in purchase/catalog files
- [x] Alembic heads checked locally — single head `023_catalog_business_active_partial`
- [x] Monitoring code ready — Sentry env-gated; APScheduler DB keepalive runs every 48h; GitHub Supabase keep-alive workflow exists
- [x] Render: `/health` + `/health/ready` → `db: ok` (verified 2026-05-21; keep-alive: `.github/workflows/render-keepalive.yml`)
- [x] Vercel: Flutter web build hardened (`vercel.json` env + `scripts/vercel-flutter-build.sh`); smoke: `scripts/verify-deploy.ps1`
- [ ] Supabase migrations (if hosted Postgres)
- [ ] Env: `DATABASE_URL`, JWT, OpenAI scan key
- [ ] Smoke: login → home → stock → purchase history → reports
- [ ] Android release APK build (`ANDROID_HOME` / Android SDK missing locally)
- [ ] Section 7 device tests (below)

---

## Section 7 — Device testing (manual)

Run on **physical** iOS 16+ and Android API 29+ before release:

- [ ] Cold start — no crash
- [ ] All bottom-nav tabs + back gesture
- [ ] Stock list loads; LIVE banner; no chip overflow
- [ ] Purchase wizard: supplier default, item search, tax preview, save
- [ ] Purchase history pull-to-refresh
- [ ] Reports overview charts
- [ ] Barcode scan — camera permission (native); manual entry (web)
- [ ] Barcode print + bulk print preview (2/row on A4)
- [ ] PDF share / print purchase + reports
- [ ] Offline purchase → sync → notification
- [ ] Staff login → home data → activity log
- [ ] Owner: staff active chips; background staff-purchase alert (if enabled)
- [ ] Keyboard + suggestion overlay above fields
- [ ] Largest system font — no critical overflow

---

## Page audit snapshot

| Page | Status |
|------|--------|
| Home (owner) | Green |
| Stock | Green |
| Reorder list | Green |
| Purchase entry / history | Green |
| Reports | Green |
| Catalog / item detail | Green |
| Barcode print / bulk | Green |
| Barcode scan | Yellow (web = manual) |
| Staff home / activity | Green |
| Notifications / Settings | Green |

---

## Agent rules (short)

- One living doc: this file + `docs/harisree/`.
- No raw `DioException` in UI — `HexaErrorCard` / `FriendlyLoadError`.
- `ref.listen` + `setState` → `addPostFrameCallback`.
- Category chips → `Wrap`.
- Financial totals on backend only.
