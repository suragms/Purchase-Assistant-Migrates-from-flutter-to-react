# Purchase Assistant — Living task board

**Last updated:** 2026-05-22 (Barcode + item code master fix)
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

## Sprint 9 — Staff privacy + UX critical (v16, May 21 2026)

| ID | Priority | Status | Summary |
|----|----------|--------|---------|
| STAFF-01 | P0 | Done | Backend redaction + Flutter hide financials (search, item detail, purchase detail, trade_intel) |
| STAFF-02 | P0 | Done | Staff home avatar → logout sheet |
| STAFF-03 | P1 | Done | 5th tab History + staff purchase list/detail routes |
| CODE-01 | P0 | Done | Auto `ITM-####` on catalog create + `POST …/generate-code` |
| CODE-02 | P1 | Done | Item code field on quick-add + post-create print SnackBar |
| ITEM-01 | P1 | Done | Compact barcode row at bottom of item detail |
| UNIT-01 | P1 | Done | `unit_utils` + bag/KG secondary on stock rows |
| SCAN-01 | P1 | Done | Camera permission UI + web scan message |
| BULK-01 | P2 | Done | Missing-code filter + staff-safe label PDF lines |
| REORDER-01 | P2 | Done | Inline reorder edit, setup page, stock category progress |
| ERROR-01 | P1 | Done | Purchase home action errors use specific messages |
| OWNER-HOME-01 | P2 | Done | `GET /stock/totals` + home movement/variance card |
| STAFF-HOME-01 | P1 | Done | Missing-code alert, today purchases, Orders tile |
| CODE-02-batch | P1 | Done | Batch create shows assigned ITM codes + print first |

---

## Sprint 10 — Warehouse UX rebuild (May 21 2026)

| ID | Priority | Status | Summary |
|----|----------|--------|---------|
| WH-00 | P0 | Done | `HexaDsWarehouse` tokens, warehouse widgets, `invalidateWarehouseSurfaces` |
| WH-01 | P0 | Done | Home live status bar, analytics skeletons, comparison strip, ring drill-down |
| WH-02 | P0 | Done | Stock list period fields + `GET /stock/{id}/intelligence` |
| WH-03 | P1 | Done | Dense stock rows, intelligence page, period sync from analytics range |
| WH-04 | P1 | Done | Purchase detail sticky action bar (owner); staff delivery in body |
| WH-05 | P2 | Done | Bulk print thermal-only (50×25 mm), collapsible filter chips |
| WH-06 | P2 | Done | `warehouseAlertsProvider` consolidation |

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
| HOME-PIE-SYNC | Done | Inventory strip (on-hand + period purchased); Items tab shell fallback; compact empty states; overview `stock_in_hand`/`purchased` when `shell_bundle`; analytics collapse; cache invalidation |
| USER-SYSTEM | Done | Identifier login (username/phone/email); user CRUD + credentials UX; tabbed `UserProfilePage`; permissions_json; server LOGIN/PASSWORD_RESET audit; staff dashboard alias + route guards; Alembic `025_user_system_rebuild` |
| USER-MGMT-V2 | Done | Email-only login; `admin` role + `is_blocked`; real email on create; bulk user actions; Users page Wrap filters + row actions + profile nav; profile tabs enriched; `028_user_mgmt_v2` migration |

---

## Sprint 11 — StockEase (May 22 2026)

| ID | Priority | Status | Summary |
|----|----------|--------|---------|
| SE-01 | P0 | Done | Phase 1: scan duplicate 409, staff route allow-list, purchase detail back nav, unit_utils bag-only kg |
| SE-02 | P0 | Done | Migration `029_stockease_operations` + stock list today/eviction fields |
| SE-03 | P0 | Done | Stock page: 3-section scroll (eviction / low / all), Wrap filters, `more_vert` actions |
| SE-04 | P1 | Done | Desktop `NavigationRail` ≥900px; stock provider 5min cache |
| SE-05 | P1 | Done | Owner home: removed analytics ring; staff home: checklist + usage CTAs |
| SE-06 | P1 | Done | Operations API: daily usage + checklist; Flutter pages `/operations/*` |
| SE-07 | P2 | Done | `/stock/missing-barcodes` alias; operational reports section on Reports |
| SE-08 | P2 | Done | Voice route removed; `formatOperationalDate` helper |
| SE-09 | P2 | Done | `029` + `030` on Supabase; `alembic_version` = `030_catalog_barcode` (2026-05-22) |

---

## Sprint 12 — Product trust (May 22 2026)

| ID | Priority | Status | Summary |
|----|----------|--------|---------|
| SE-10 | P0 | Done | Stock row last-update line; audit feed API; undo-last PATCH + SnackBar |
| SE-11 | P0 | Done | Daily snapshots list/materialize API; today block on intelligence page |
| SE-12 | P1 | Done | `/catalog/duplicates` page + duplicate clusters API |
| SE-13 | P1 | Done | Fuzzy search cap `kCatalogFuzzySearchMax=8`; inline picker already max 8 |

---

## Sprint 13 — Operational speed (May 22 2026)

| ID | Priority | Status | Summary |
|----|----------|--------|---------|
| SE-19 | P0 | Done | Quick +/- sheet; stock row actions entry |
| SE-20 | P0 | Done | Stock scan FAB `?return=stock`; post-scan quick patch + assign barcode |
| SE-21 | P1 | Done | Final stock row layout (code line, signed Today/Used, last update) |
| SE-22 | P1 | Done | Bulk actions: print, reorder setup, duplicates, archive picker |
| SE-23 | P2 | Done | Barcode PDF: thermal 50×25, A4/thermal chips, Code128/QR modes |

---

## Sprint 14 — Staff clarity + intelligence (May 22 2026)

| ID | Priority | Status | Summary |
|----|----------|--------|---------|
| SE-25 | P1 | Done | `HomeMultiAlertStrip` + `GET /stock/alerts/summary` |
| SE-26 | P1 | Done | Checklist Morning/Midday/Evening tabs + summary API |
| SE-27 | P1 | Done | `/stock/dead`, `/stock/fast-moving`, `/stock/slow-moving` + reports chips |
| SE-28 | P2 | Done | Operational reports drill-down from Reports section |

---

## Barcode + item code master fix (May 22 2026)

| ID | Priority | Status | Summary |
|----|----------|--------|---------|
| BC-01 | P0 | Done | Migration `030`: `catalog_items.barcode` + unique index |
| BC-02 | P0 | Done | API: from-scan create, PATCH item-code/barcode, lookup + 409 |
| BC-03 | P0 | Done | `/catalog/quick-add-from-scan` minimal create (no ITM auto) |
| BC-04 | P1 | Done | `/stock/missing-barcodes` TabBar + assign/edit sheets; print → single |
| BC-05 | P1 | Done | Scanner: web camera attempt, manual/photo/retry fallback, found-actions sheet |
| BC-06 | P1 | Done | Labels: symbology=barcode, PDF 2/4-col; bulk selection provider + debounce |
| BC-07 | P1 | Done | `pytest test_barcode_item_code.py`; docs matrix in `MASTER_REFERENCE.md` |

**Deploy:** Supabase schema at Alembic **`030_catalog_barcode`** (2026-05-22): MCP `harisree_030_catalog_barcode` + `alembic upgrade head` stamped `029→030`. Columns: `barcode`, `eviction_days`, `daily_usage_logs`, etc.

**E2E prod (2026-05-22):** Use **https://purchase-assiastant.vercel.app** (not `purchase-assistant.vercel.app`). `/stock` crash root cause: `as num?` on API decimal **strings** — fixed with `coerceToDouble` in stock rows. Push + Vercel redeploy required.

---

## Sprint 19 — Owner dashboard warehouse rebuild (May 22 2026)

| ID | Priority | Status | Summary |
|----|----------|--------|---------|
| OD-01 | P0 | Done | Owner `/home`: direct warehouse control-center order; no dead collapsed Recent/Low/Movement cards |
| OD-02 | P0 | Done | Header/live strip: short warehouse name, WH code + OWNER pill, synced/offline clarity, health center sheet |
| OD-03 | P0 | Done | Stock overview: stock value, tracked items, purchased/current/moved-sold comparison bar, owner-friendly language |
| OD-04 | P1 | Done | Quick grid + alert pills: Scan/Stock/Purchase, Reports/Barcode/Users; business terms for delivery, reorder, missing labels |
| OD-05 | P1 | Done | Warehouse analytics bottom sheet reuses ring/tabs/ranked list; shell FAB quick actions aligned with warehouse workflow |

**E2E:** hard refresh `/home` → status strip/health sheet → period tabs → stock overview analytics → recent/low/movement rows → FAB quick actions.

---

## Sprint 20 — Stock detail + ledger operations rebuild (May 22 2026)

| ID | Priority | Status | Summary |
|----|----------|--------|---------|
| SL-01 | P0 | Done | Stock list: purchased/current/moved/status columns, no duplicate scan FAB, no eviction status chip |
| SL-02 | P0 | Done | Quick edit: +1/+5/+10 and -1/-5/-10, Sale/Usage/Damage/Correction/Transfer ledger reasons |
| SL-03 | P0 | Done | Item detail: stock summary, purchase rows with invoice/detail navigation, barcode generate/print/copy actions, ledger tabs |
| SL-04 | P1 | Done | Search: quick filters and 2-second fallback instead of stuck skeletons |
| SL-05 | P1 | Done | Add item + bulk print: optional item code/rates, barcode guidance, compact missing-code/barcode/reorder filters |

**E2E:** `/stock` filters → row detail → barcode generate → quick stock edit sale/damage → item ledger tabs → search empty/loading fallback → bulk print preview/PDF.

---

## Sprint 21 — Reports BI master rebuild (May 22 2026)

| ID | Priority | Status | Summary |
|----|----------|--------|---------|
| RPT-01 | P0 | Done | `/reports` BI shell: scrollable tabs + More sheet, `ReportsSummaryCard`, `?tab=` deep link, export/share app bar |
| RPT-02 | P0 | Done | Shared BI widgets: `WarehouseRingSection`, `BreakdownLegendList`, `ReportsBiSlice` under `features/reports/widgets/bi/` |
| RPT-03 | P0 | Done | Categories + Subcategories tabs (`analyticsTypesTableProvider`); drill routes `/reports/category-drill`, `/reports/subcategory-drill` |
| RPT-04 | P0 | Done | Slow/Dead tabs + `SlowMovingRow`; enriched `operations/reports/summary` (idle_days, aging_bucket, insight_key) |
| RPT-05 | P1 | Done | `/reports/item/:catalogItemId` canonical item BI (embedded stock intelligence) |
| RPT-06 | P1 | Done | `GET /reports/period-comparison`, `GET /reports/movement-summary`; `ReportsInsightsStrip` + movement tab |
| RPT-07 | P1 | Done | Invalidation: `reportsPeriodComparisonProvider`, `reportsMovementSummaryProvider` in `invalidateAnalyticsData` |
| RPT-08 | P2 | Done | Home stock card analytics icon → `/reports?tab=subcategories`; operational list uses `SlowMovingRow` |

**E2E:** `/reports?tab=subcategories` from Home → ring tap drill → slow row → `/stock/intelligence/:id` → period comparison on summary → movement tab totals.

---

## Sprint 22 — Barcode scan + stock audit rebuild (May 22 2026)

| ID | Priority | Status | Summary |
|----|----------|--------|---------|
| AUD-01 | P0 | Done | Backend: `business_id` on `stock_audits`, scoped `/stock-audits`, `complete` applies ledger, `verify-count`, approval threshold |
| AUD-02 | P0 | Done | `WarehouseScanActionSheet`: counted stock, diff colors, mandatory reasons, mini ledger, save |
| AUD-03 | P0 | Done | Scanner UX: light frame, history/audit actions, `?return=search`, pending sync banner |
| AUD-04 | P1 | Done | Audit session pages + `activeStockAuditProvider` + complete → summary |
| AUD-05 | P1 | Done | Scan history page; `HomeStockAuditStrip` KPIs |
| AUD-06 | P1 | Done | `OfflineStore.queueStockVerify` + replay on sync |
| AUD-07 | P2 | Done | `pytest` stock audit + verify-count; `dart analyze` barcode module |

**E2E:** scan → counted qty + reason → stock updates → audit session → complete → home audit pills.

---

## Sprint 18 — Stock warehouse list rebuild (May 22 2026)

| ID | Priority | Status | Summary |
|----|----------|--------|---------|
| ST-01 | P0 | Done | `stock_page.dart`: flat 72dp rows, sticky 32dp period/unit/status pills, 4-icon app bar |
| ST-02 | P0 | Done | `stock_quick_edit_sheet` (+1/+5/manual/reason); `stock_operational_row`; period via `stockPagePeriodProvider` |
| ST-03 | P1 | Done | Advanced filter sheet only (category/supplier/reorder/missing code/barcode); bulk actions in sheet footer |
| ST-04 | P1 | Done | Staff `/staff/stock` `StockPageMode.staff`; desktop ≥1100 split + `Item detail` intelligence |
| ST-05 | P1 | Done | Shell bottom nav 56dp / 20dp icons; scroll-hiding 48dp scan FAB |

**E2E:** stock filters instant apply → quick edit → row detail → staff route hides owner analytics.

---

## Sprint 17 — Production UX + PDF/print (May 22 2026)

| ID | Priority | Status | Summary |
|----|----------|--------|---------|
| PX-01 | P0 | Done | `barcode_operation_errors.dart` + `OperationalAsyncButton`; no generic snackbars on print/scan |
| PX-02 | P0 | Done | `showOperationalStockFilter` sheet/panel (1100px); stock + bulk: search + filter icon only |
| PX-03 | P0 | Done | Bulk print rebuild: segmented A4/Thermal/QR, sticky bar, batch partial failure, web print guard |
| PX-04 | P1 | Done | Desktop ≥1100: list + `BulkBarcodePrintPreviewPanel` |
| PX-05 | P1 | Done | Scanner: 55% viewport, 3 fallback actions, web `BarcodeDetector` photo path |
| PX-06 | P1 | Done | `barcode_pdf_service` symbology validation; `barcode_operation_errors_test.dart` |

**E2E:** purchase-assiastant — bulk PDF/preview, filter sheet, scan photo (Chrome), stock list without chip wall.

---

## Sprint 16 — StockEase UX rescue (May 22 2026)

| ID | Priority | Status | Summary |
|----|----------|--------|---------|
| UX-01 | P0 | Done | `HexaOp` operational tokens (16dp gutter, 44dp buttons, 64–72dp rows) |
| UX-02 | P0 | Done | Owner home: 3×2 quick grid, horizontal alert pills, compact totals, 52dp accordions |
| UX-03 | P1 | Done | Staff home: scan-first 64dp CTA, alert pills, dense low-stock rows |
| UX-04 | P1 | Done | Scanner: post-scan `scan_stock_result_sheet` (+1/+5); web photo via `analyzeImage`; not-found manual |
| UX-05 | P1 | Done | Bulk print: sticky bottom bar, 64dp rows, Wrap filters, determinate progress, desktop 2-col ≥900px |
| UX-06 | P1 | Done | Item code edit on catalog detail + barcode print; missing-labels 64dp rows |
| UX-07 | P1 | Done | Shell FAB 56dp / bottom bar 60dp; stock `perPage` 50 + `coerceToDouble` audit on hot paths |
| UX-08 | P2 | Done | Pushed `57655a2`; Vercel prod smoke: `/home`, `/stock`, `/barcode/scan`, `/barcode/bulk-print` |

**E2E checklist (purchase-assiastant):** hard refresh → home tabs/accordions → stock scroll + filters → scan manual code → bulk select + PDF preview → missing-labels tabs.

---

## Sprint 15 — Production polish (May 22 2026)

| ID | Priority | Status | Summary |
|----|----------|--------|---------|
| SE-31 | P2 | Done | Shell pending-sync banner (`OfflineStore`) |
| SE-32 | P2 | Done | Local notifications: usage, checklist, low-stock digest schedules |
| SE-33 | P2 | Done | Biometric re-login (`local_auth` + saved email, refresh token) |
| SE-34 | P3 | Deferred | Assistant/voice modules unused (routes redirect); physical delete later |
| SE-35 | P2 | Done | Docs: this board + `MASTER_REFERENCE` stock row note |

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
