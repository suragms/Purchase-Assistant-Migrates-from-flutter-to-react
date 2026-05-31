# Purchase Assistant — Living task board

**Last updated:** 2026-05-29 (Master prompt FIX-1–15 verification)

## Master prompt FIX-1–15 (2026-05-29)

All 15 fixes verified in codebase; pytest 10 passed; flutter repair tests 13 passed. Reports chart clamp + warehouse ring type fix ready for deploy.

- [x] FIX-1–12 — shipped (see sections below)
- [x] FIX-13–15 — empty states, dense rows, scrollable stock tabs / reports chips
- [ ] Manual: commit delivery → stock SYSTEM column refreshes without pull-to-refresh
- [ ] Deploy Vercel after reports chart fix

## Screenshot fixes (2026-05-29)

- [x] Compact sheet blank gap — `HexaResponsiveSheetViewport` compact uses `Align(heightFactor: 1)`; stock row actions → `showHexaBottomSheet`
- [x] Stock list 4-column layout — ITEM | SYSTEM | PHYS | DIFF (owner + staff); no STATUS/PEND columns; pending via chips + left border only
- [x] Verification log — `purchase`/`delivery_receive` → `DELIVERED` label
- [x] Reports period — reactive sync from `appSelectedPeriodProvider` via `listenManual`
- [x] Delivery commit invalidation — already via `invalidateAfterDeliveryCommit` hub

- [x] **Invalid argument: 120** — `ReportsOverviewChartSection` used `.clamp(120, maxD)` while `maxD` from `viewportHeight: 280` is ~90; fixed `reportsOverviewChartSize()` + unit test
- [ ] **401 `/v1/me/businesses`** — expired/invalid session (not Hive/DB); sign in again; redeploy after chart fix so error boundary no longer masks auth
- Note: Hive “Got object store box…” logs are normal offline cache init, not Postgres errors

## Master repair verification (2026-05-30)

FIX-1–FIX-12: already shipped (invalidation hub, sheets, navigation, backend filters, undo, disputed_cnt, delivery verify banner, commit dialog). Verified by pytest + targeted flutter tests.

- [x] **FIX-13** `HexaEmptyState` on stock Changes/Movement tabs + reports movement tab; home activity feed already had empty state
- [x] **FIX-14** Dense warehouse row — `rowMinHeight` 72; ledger `current_stock` SSOT; removed PUR/human-id from `deliveryMetaLine`
- [x] **FIX-15** Reports uses horizontal scroll `ChoiceChip` row (no `TabBar`); stock operational `TabBar` already `isScrollable: true`
- [x] Tests: backend 10 passed; flutter `delivery_invalidation`, `navigation_ext`, `sheet_compact_height`, `stock_row_metrics`
- [ ] **Deploy:** Alembic **044** on Render Postgres before API deploy
- [ ] Manual: commit delivery → stock SYSTEM column refreshes without pull-to-refresh

## FIX_TODO_MASTER (2026-05-30)

Wave 1 (shipped):

- [x] **P0-003** Undo guard — `opening_stock` + `opening_stock_setup` adjustment types blocked for non-owner/admin
- [x] **P0-006** Trade list `status` filter — payment + delivery statuses (`dispatched`, `arrived`, `stock_committed`, …)
- [x] **P0-011** Desktop stock detail empty state — icon + subtitle
- [x] **P1-016** Delivery deep links — `filter=` chips + `?delivery_status=` alias on purchase history
- [x] **P1-017** Stock page realtime — `realtimeInvalidationProvider` → reset merged list + warehouse invalidation
- [x] **P1-018** Low-stock cron fetch — single `shortage` sweep (was 3× low/critical/out)
- [x] **P1-011** Activity `action_route` on dispatch / arrive / commit staff activity
- [x] Tests: `test_stock_undo`, `test_low_stock_operations`, `test_trade_purchase_delivery_pipeline`

Already done (prior sprints — do not redo): P0-001, 002, 004, 005, 007–010; P1-002–004, 010, 013–014, 020–021; P1-006 badge from merged feed.

Wave 2 (partial / backlog):

- [x] **P1-005** Home KPI tiles capped ~100px (`childAspectRatio` / 100)
- [x] **P1-008** Stock `TabBar` `isScrollable: true` (already in `stock_operational_top_bar`)
- [x] **P1-012 / P1-019** `formatPurchaseHumanDate` on purchase history rows
- [x] **P1-001** Stock warehouse row dense spec — 72px row, ledger qty, no PUR in meta line
- [x] **P1-007** `HexaEmptyState` on stock changes/movement + reports movement tab
- [x] **P1-009** Reports 4 primary chips + More sheet (`ReportsBiTabX.primaryRow` / `moreSheet`)
- [x] **P1-015** Idempotency documented in `backend/alembic/versions/README.md` (037 unique)
- [x] **P1-022 / P2-018** Alembic 026/027 gap documented in `backend/alembic/versions/README.md`
- [ ] Manual QA matrix (from `docs/harisree/TODO_MASTER_LIST.md`)

### P2 backlog (implement when QA flags)

P2-001 … P2-018 — owner tasks sheet, reports export polish, admin_web SQL PIN (separate app), stale cache TTLs, duplicate purchase guard UX, stock PDF column order, etc. See `docs/harisree/TODO_MASTER_LIST.md`.

### P3 polish backlog

P3-001 … P3-015 — animations, haptics, desktop column resize, pricing table doc-only, etc.

## Navigation fix (2026-05-30)

- [x] **NAV-005** Item entry / catalog quick-add pop fallback → `/purchase` (not `/purchase/new`)
- [x] **NAV-003** Verify delivery sheet close always invalidates purchase detail + delivery pipeline
- [x] **NAV-006** `ReportsPage.didChangeDependencies` syncs `?tab=` query; smoke test `reports_tab_deep_link_test.dart`
- [x] **NAV-002** `shellReturnBranchProvider` + `goShellTab` / `popShellTabOrGoHome`; home dashboard cards use cross-tab helper (not root `push`); Reports `PopScope` + contextual back; bottom nav clears return branch
- [x] **NAV-004** Stock scroll persist before item navigate + restore on return from catalog item
- [x] Tests: `navigation_ext_test.dart`, `reports_tab_deep_link_test.dart`
- [ ] Manual QA matrix below

| Flow | Pass |
|------|------|
| Purchase wizard → Add item → back (no blank / web error) | [ ] |
| Empty-stack back from item entry → purchase list (not blank new form) | [ ] |
| Home KPI → Reports → system back → Home | [ ] |
| Home → Reports → bottom nav Stock (no stuck Reports body) | [ ] |
| `/reports?tab=items` cold URL selects Items tab | [ ] |
| Purchase detail → Verify → dismiss sheet → status refreshes | [ ] |
| Stock list scroll → View item → back restores scroll | [ ] |

## Stock engine rebuild (2026-05-30)

- [x] **STOCK-001** Delivery commit invalidation — `invalidateAfterDeliveryCommit` busts stock list, home dashboard, delivery pipeline, **`homeStockAttentionCountProvider`**
- [x] **STOCK-002** Undo last change via `apply_stock_movement` + `stock.changed` event (prior sprint)
- [x] **STOCK-003** `compute_expected_system_qty` includes quick purchases (prior sprint)
- [x] **STOCK-004** Idempotency — `UNIQUE (business_id, idempotency_key)` on `stock_movements` (037 migration; no new 043 needed)
- [x] **STOCK-005** Supplier N+1 — bulk fetch in `list_stock`, opening-stock setup, low-stock slice, reorder list, opening-missing
- [x] **STOCK-006** Migration **044** — clamp negative `current_stock` + `CHECK (current_stock >= 0)`
- [x] **STOCK-007** Physical count `difference_qty = counted - system_at_count` (prior sprint + tests)
- [x] **STOCK-008** PATCH delivery rejects `is_delivered=True`; commit idempotency (prior sprint)
- [x] **STOCK-009** Opening stock locked — staff blocked on PATCH (prior sprint)
- [x] **UI display** Owner list **STOCK** column = `current_stock` (ledger); staff **PHYS** + truck badge; expected/reconciliation owner-only in item snapshot expansion tile
- [x] Tests: `test_physical_count_diff_sign`, `test_stock_undo`, `test_warehouse_logic_fixes`, `test_purchase_stock_increment`; Flutter `stock_row_metrics_test`, `stock_dense_row_test`, `delivery_invalidation_test`
- [ ] **Deploy:** apply migration **044** on Render Postgres before API deploy
- [ ] Manual QA: commit delivery → stock list + home attention badge refresh; owner row shows ledger qty not expected formula

**Backlog (out of scope):** available/reserved stock, returned stock, damaged stock in list UI.

## Owner home UX rebuild (2026-05-29)

- [x] Compact alert chips: Low · Opening · Out · Pending delivery (red when > 0)
- [x] Order: header → chips → **sticky period** → purchases → warehouse → stock lists → **Tools** → recent activity
- [x] Removed **My tasks** from home (Settings → Owner tasks)
- [x] `HexaPageErrorBoundary`: type-cast errors fatal again (fixes silent blank Home/Stock/Reports)
- [x] Recent activity: purchase · delivery verified · staff qty · stock corrections only
- [ ] Deploy Flutter Vercel + hard refresh

## Owner dashboard blank fix (2026-05-29)

- [x] **Root cause:** API returns decimals as **strings** — `as num?` casts in dashboard parse + status counts crashed Home (gray blank + console `not a subtype of type num?`)
- [x] Safe coercion via `coerceToInt` / `coerceToDouble` in `homeDashboardDataFromApiSnapshot`, `stockStatusCountsProvider`, delivery pipeline, warehouse alerts, home cards
- [x] Stock page: **All / Low / Out** quick chips above list; subcategory in row meta; bolder metric numbers
- [x] Low stock + stock PDF/CSV export: web download + mobile share
- [x] Notifications: **Order now** on staff reorder-request alerts (owner)
- [ ] Deploy Flutter to Vercel + hard refresh

## Staff system stock + barcode UX (2026-05-29)

- [x] Staff can set **System stock** (ledger) from scan sheet + quick stock sheet (Physical | System toggle)
- [x] Backend: staff system PATCH notifies **owners** (`stock_correction` alert) + audit via existing movement log
- [x] Scan summary shows **last system edit by** + timestamp
- [x] Barcode scan: deferred camera init, faster debounce (900ms), app bar icons → single **More** menu
- [x] Scan action sheet: compact (no 62% blank sheet), label print toolbar unchanged (settings in one button)
- [x] Tests: `test_staff_system_stock_notify.py`

## Low stock mobile UX v2 (2026-05-29)

- [x] Item row ~90px: name · stock · status · **+ Stock** + **Order** only; overflow → detail sheet
- [x] Detail sheet: physical, reorder, supplier, secondary actions (reorder lvl, receive, profile)
- [x] Categories collapsed by default; single **OUT n** badge per category
- [x] Segmented tabs: All · Out · Bought · Pending · Delivery with counts
- [x] Filter sheet: content-sized, sticky Apply (no 70% empty gap)
- [ ] Manual QA on device (owner + staff low-stock routes)

## Low stock mobile UX (2026-05-29)

- [x] Compact row: bold colored metric tiles (System / Physical / Reorder / Purchased) + lifecycle pills + labeled action chips
- [x] Search bar: single **Filters** sheet (scope + subcategory) — removed 5 icon clutter
- [x] Staff inform-owner: local **Informed** state + notification provider invalidation
- [x] Bottom sheets: `compact: true` on reorder level, update stock, quick stock patch (no top blank gap)
- [x] Staff home: removed duplicate Purchases/Low stock quick-links row (Tools grid already has them)
- [ ] Manual QA: low stock tabs (All/Pending/Out/Bought/Delivery), staff inform owner, reorder sheet height

---

## Production hotfix — Home/Reports blank (2026-05-29)

- [x] **Root cause:** `Badge` always builds `label` — several grids used `badge!` or unsafe labels on tiles **without** a count (owner quick actions, staff tools, staff nav)
- [x] **Why so many console errors:** one build crash → Flutter retries every frame → hundreds of `Another exception was thrown` lines (not hundreds of different bugs)
- [x] Shared fix: `HexaCountBadge` widget; applied on owner + staff home tools + staff bottom nav
- [x] Per-tab `HexaPageErrorBoundary` on Home, Stock, Purchases, Staff home (IndexedStack builds all shell tabs at once)
- [x] Delivery pipeline API: 15s timeout so staff KPI row does not shimmer forever
- [x] `HexaPageErrorBoundary`: null-check errors are fatal again (no silent grey loop)
- [x] Critical alert cards: removed `Spacer` in unbounded column
- [x] Render cron: `POST /internal/whatsapp-reports/send-due` stub (was 404)
- [x] Tests: `home_owner_quick_actions_test.dart`, `test_internal_cron.py`

**Deploy:** push Flutter to Vercel + API to Render. Set `WHATSAPP_REPORTS_CRON_SECRET` on API (must match cron job header). Users: hard refresh or sign out/in once.

---

- [x] Fix checkbox: optimistic state no longer cleared on success (tasks stay checked)
- [x] Per-business default seed (6 tasks); templates API `GET/PUT /operations/checklist/templates`
- [x] Owner: **Settings → Owner tasks** — Arrange list + Check today tabs
- [x] Staff tasks: pull-to-refresh, auth-aware provider, clearer 401 retry copy
- [x] Backend test: `test_checklist_operations.py`

**DB:** ensure migration `029_stockease_operations.sql` applied (`staff_checklist_templates`, `staff_checklist_completions`).

**Manual QA:**

| Check | Pass |
|-------|------|
| Staff Tasks → tick Opening stock → stays checked | [ ] |
| Midday / Evening tabs show 2 tasks each (6 total) | [ ] |
| Owner → Arrange → add task → Save → staff sees new task | [ ] |
| After stale session: Retry or sign out/in (no 401 loop) | [ ] |

---

## Barcode scan + missing labels + roles (2026-05-29)

- [x] Scanner: stop camera on detect, 1.2s debounce, fewer symbologies, no full-catalog load (server search)
- [x] Unknown barcode: clear copy + read-only gate on assign/create
- [x] Missing labels: scan shortcut, bulk print, staff **Inform owner** (`missing_barcode` alert)
- [x] Permissions: `/v1/me/businesses` returns `permissions`; Flutter `session_permissions.dart`
- [x] API: `stock_edit` for barcode/item-code patch; `barcode_print` for label batch
- [x] Guide: `docs/harisree/BARCODE_WORKFLOW.md`

**Manual QA:** see BARCODE_WORKFLOW.md table.

---

## Ship now (automated ✅ — you run deploy)

1. **Prod DB:** `cd backend && alembic upgrade head` (migrations **040**, **041**, **042**).
2. **API:** deploy Render backend from current `main`.
3. **Web:** publish `flutter_app/build/web` to Vercel (or host).
4. **Smoke:** owner Home → Stock → Purchase → Reports; staff **Deliveries** + **Tasks** tabs.
5. **Sign out/in** once after deploy if session was stale.

---

## Home dashboard blank + purchase party prefill (2026-05-29)

- [x] **Home gray blank:** opaque `ColoredBox` on shell + home body; `AlwaysScrollableScrollPhysics` for pull-to-refresh; sync `shellCurrentBranchProvider` on Home mount + force refresh
- [x] **Home slow/stuck load:** inventory summary 12s timeout → empty fallback; purchase card skeleton shows Retry + `forceStopRefreshing`; refresh throttle 8s
- [x] **New purchase party fields:** removed auto last-supplier pref fill; fresh `/purchase/new` clears Hive/prefs draft + all party/terms controllers; no broker/commission carry-over

**Manual QA:**

| Check | Pass |
|-------|------|
| Owner `/home` shows dashboard cards (not gray blank) after load | [ ] |
| Pull-to-refresh on home reloads totals | [ ] |
| **New purchase** → supplier + broker fields empty; commission blank | [ ] |
| Resume draft banner still works via `?resumeDraft=true` | [ ] |

---

## Item entry back buttons + web pop crash (2026-05-29)

- [x] **Root cause:** purchase item entry opened via `Navigator.push(MaterialPageRoute)` but back/close used `GoRouter.pop` → empty stack throws on web (`main.dart.js Uncaught Error`)
- [x] `navigation_ext.dart`: `popOverlay` (dialogs) + `popImperativeOrGo` (imperative routes + deep-link fallback)
- [x] `PurchaseItemEntrySheet`: `_popSheet()` uses `popImperativeOrGo(fallbackGo: '/purchase/new')`; discard dialog uses `popOverlay`
- [x] `PurchaseEntryWizardV2`: all dialog dismissals → `popOverlay`; post-save exit → `popOrGo('/purchase')`; PopScope step-back uses post-frame `setState`
- [x] `CatalogItemCreatePage`: `_popPage()` with purchase/catalog fallback

**Manual QA (item entry back — web + mobile):**

| Check | Pass |
|-------|------|
| Purchase wizard → Add item → back (clean) returns to wizard | [ ] |
| Purchase wizard → Add item → edit fields → back → discard dialog → Leave | [ ] |
| Purchase wizard → Add item → **New catalog item** → back on step 1 exits | [ ] |
| Catalog quick-add from purchase → save → returns item to line | [ ] |
| Browser back on item entry (no console `Uncaught Error`) | [ ] |

---

## Staff purchase history + owner reorder alerts (2026-05-29)

- [x] **`/staff/purchase-history`** route wired (was redirecting to deliveries)
- [x] Purchase list: Today / Week / All + search + Pending/Delivered filters — **no prices** (supplier, qty, status only)
- [x] Low stock tab: search + Critical filter + **Inform owner** → `/staff/low-stock`
- [x] Staff purchase history: owner-style grouped rows, no ₹; dedicated `staffTradePurchasesHistoryProvider` (fixes 401 spam from owner list provider)
- [x] Owner home alerts: **Staff reorder requests** card (`reorder_request` notifications)
- [x] Backend `notify-owner`: `category=staff`, `priority=high`, `triggered_by_user_id`, targets owner/manager/admin
- [x] Notifications: `reorder_request` maps to **Staff** category (not hidden under System)

**Manual QA:**

| Check | Pass |
|-------|------|
| Staff home → **Purchase history** opens list | [ ] |
| Search + Pending filter works; no ₹ on rows | [ ] |
| Low stock tab → Inform owner → low stock dashboard | [ ] |
| Staff informs owner → owner sees alert on home + notifications | [ ] |

---

- [x] **Root cause (API/Hive fail):** `purchasesAsync.value` on errored provider threw `StateError` in build → global “Could not load the app”; use `valueOrNull`
- [x] **Root cause (cold web):** `OfflineStore` Hive reads threw `HiveError: Box not found` before init — safe `_openBox()` no-op reads
- [x] Nested scroll: tab bodies use `reportsNestedListBody` (shrinkWrap) inside `CustomScrollView`; removed redundant ListView wrapper on items/suppliers/brokers
- [x] Mobile tabs: **4 primary** (Overview, Categories, Items, Suppliers) + **More** sheet (Stock intel, Subcat, Brokers, Dead, Usage, Stock mvmt)
- [x] Route passes `initialTab` from `?tab=` query (no `GoRouterState.of` in initState)
- [x] Reports parse miss: soft fallback instead of throwing `StateError`
- [x] Smoke test: `test/reports_page_smoke_test.dart` (+ provider error survival)
- [x] `HexaPageErrorBoundary` wraps `/reports` route (page-scoped retry, not whole-app crash)

**Manual QA (Reports):**

| Check | Pass |
|-------|------|
| Direct URL `/reports` loads (no global error card) | [ ] |
| Overview + Categories + Items tabs scroll as one page | [ ] |
| More sheet opens Stock intel / Dead / Movement | [ ] |
| `/reports?tab=items` deep link selects Items | [ ] |

---

- [x] Central `auth_failure_policy.dart`: `authSessionExpiredProvider` + refresh failure cap (2 in 60s)
- [x] Dio: 401/403 on business routes → refresh; second 401 after retry → terminal logout
- [x] Router redirect when session null **or** `authSessionExpiredProvider`
- [x] Pause home 60s poll + realtime poll + notification coordinator when session invalid
- [x] Home session banner **Sign in again** → logout + `/login`
- [x] Unified `CatalogItemCreatePage` (supplier/broker → subcategory → name/unit/weight → optional code); 2 steps
- [x] All add-item routes + purchase wizard → `/catalog/quick-add` with supplier/broker query params
- [x] PopScope step-back on catalog create + supplier/broker wizards

**Manual QA (auth + item create) — run after Vercel deploy:**

| Check | Pass |
|-------|------|
| Expired token: one refresh attempt → login screen; no 60s 401 loop in console | [ ] |
| Home/stock/notifications stop polling after logout | [ ] |
| Purchase wizard **Add item**: supplier/broker prefilled → save → returns new item on line | [ ] |
| Catalog type list FAB **Add item**: same 2-step flow | [ ] |
| System back on step 2 → step 1; step 1 back exits wizard | [ ] |
| Supplier/broker create wizards: system back steps back before exit dialog | [ ] |

---

## Staff home + stock table (2026-05-29)

- [x] Staff home top KPI row: Pending / Delivered / Low stock (`deliveryPipelineProvider`)
- [x] Warehouse + purchase stats boxes always visible (not collapsed)
- [x] My Tasks → bottom nav **Tasks** tab (`/staff/tasks`); Settings via profile sheet
- [x] Pending delivery cards use `tradePurchasesForAlertsProvider` (not 30-day history filter)
- [x] Staff stock table: SYSTEM / PHYS / DIFF + ITEM column border; owner wide 6-col mismatch removed
- [x] **Supabase live audit (2026-05-29):** `alembic_version` = `042_catalog_stock_list_sort_index`; `delivery_status` + indexes present; 0 invalid statuses
- [ ] **Render API:** confirm `DATABASE_URL` points at same Supabase project (not a stale DB)
- [ ] Optional: `python -m scripts.backfill_delivery_status` if stock_committed rows lack movements

**Manual QA (staff) — after deploy:**

| Check | Pass |
|-------|------|
| Home top: 3 KPI cards show numbers (0 ok) | [ ] |
| Warehouse + Purchases boxes load (not blank grey) | [ ] |
| Tasks tab → full checklist (Morning/Midday/Evening) | [ ] |
| Profile → Settings opens `/staff/settings` | [ ] |
| Stock tab: bordered table, SYSTEM has values | [ ] |

---

## PLAN.MD execution (2026-05-28)

**Controller:** [PLAN.MD/README.md](PLAN.MD/README.md) (23 files)

### Phase 0 — manifest
- [x] All 23 MD files on disk under `PLAN.MD/`
- [x] `PLAN.MD/README.md` status board + V1/V2 map

### Phase 1 — audits (tickets extracted; implement in Phase 2+)
- [x] 1–14 read → P0 backlog: stock formula truth, provider `ref.read`, polling, delivery pipeline, dedupe files, UI sheets
- [x] Reconciled done: notifications blank cards (`7fcae7c`), low-stock dashboard, stock ITEM/SYSTEM/PHYS/DIFF

### Phase 2 — V2 P0
- [x] Task 1: `item_detail_providers` → `ref.read` for parallel futures
- [x] Task 2: home single 60s poll + throttle on full invalidate
- [x] Task 3: migration `040_purchase_delivery_tracking` + model columns
- [x] Task 4: Flutter `deliveryStatus` on `TradePurchase`
- [x] Task 5: delivery pipeline API (`dispatch` / `arrive` / `verify` / `commit-stock` / `delivery-pipeline`); PATCH delivery = revert only; stock on commit only
- [x] Tasks 6–7: `total_delivered_qty` / `total_pending_delivery_qty` on stock detail API + snapshot card
- [x] Task 8: deleted `catalog_item_detail_page.dart` (~3k lines); `/catalog/item/:id` → `ItemDetailPage`; edit → `ItemEditPage` + `catalog_item_defaults_edit_form.dart`
- [x] Task 9: purchase delivery stock idempotency + `test_delivery_double_commit_is_idempotent`

### Phase 3 — rebuild MDs 17–20
- [x] Reconciled with 2026-05-28 warehouse sprints + notification card fix

### Phase 4 — V2 P1
- [x] Staff/owner home, stock table, reports overlap (prior commits)
 (Task 19 backlog)
- [x] Duplicate cleanup (2026-05-29): deleted monolith catalog detail; redirect `/stock/reorder-suggestions` → `/stock/reorder`; removed `reorder_suggestions_page`, `low_stock_owner_page`
- [x] Full duplicate cleanup (2026-05-29, validated): `ItemDetailPage` + redirects; `StockPage` 4-tab hub; stock history → `StockItemHistoryPanel` on item detail + `/stock/:id/history` redirect; `notification_center_provider` + `homeWarehouseAlertsProvider` + `notificationFeedForUiProvider`; `AppShellBody` (owner/staff); `StockSummaryWidget` via `StockRowMetrics.stockSummary` + quick view + bulk print; opening-stock `opening_stock_sheets.dart` barrel; deleted ~15 duplicate pages; `flutter analyze` + `trade_date_range_parity_test` pass

### Duplicate cleanup — route audit (2026-05-29)

| Route / feature | Status |
|-----------------|--------|
| `/get-started` | Redirect → `/login` |
| `/operations/daily-usage` (DailyUsagePage) | Active — owner route |
| `/item-analytics/:name` | → `ItemAnalyticsRedirectPage` → catalog item when resolved |
| `/reports/item-detail` | → `ReportsItemRedirectPage` → catalog or thin fallback |
| Reports BI (`reports_bi_tab.dart`) | Active on `/reports` |
| `/stock/dead`, `/fast-moving`, `/slow-moving` | Redirect to `/reports?tab=…` |
| `/stock/changes`, `/movement`, `/today-feed` | Redirect to `/stock?tab=…` |

**Manual QA:** Owner home alerts + notifications tabs; stock Warehouse/Changes/Movement/Today; reports item drill; catalog item edit; staff scan → quick stock sheet.

### Performance sprint (2026-05-29)

- [x] Home: debounced `_scheduleRefresh` (500ms); single 60s poll; notification coordinator skips periodic timer on Home tab; realtime yields `RealtimeInvalidationSignal` (alerts-only vs full refresh)
- [x] Item detail: `itemDetailStockProvider` / `itemDetailCatalogProvider` from bundle; sections stop duplicate `stockItemDetailProvider` fetches; revision → `itemDetailBundleProvider` only
- [x] `stockListProvider` keepAlive TTL **30s**; lazy heavy sections on mobile item detail (400ms defer)
- [x] `HexaResponsive.sectionGap(context)` on owner home blocks; search list padding includes keyboard `viewInsets`
- [x] **Refresh storm fix:** `invalidateWarehouseSurfacesLight` (no KPI/aggregate bump); realtime poll signals only (no invalidate inside poll); shell stops watching realtime; removed global `businessDataWriteRevision` listener on item detail; bundle drops catalog-wide `tradePurchasesCatalogIntel` + snapshot drops extra intelligence fetch; stock writes pass `itemId` for scoped bust
- [x] **Production perf closure (2026-05-29):** `BusinessWriteEvent` + scoped listeners (item detail, category, trade ledger); backend `purchase.changed` with `item_ids`; `tradePurchasesForItemProvider` (per-item API); realtime `affectedItemIds`; `stockItemDetail` + notifications **30s** keepAlive; removed dead `homeInsights` invalidation + `realtime_notifications_provider`; `test/realtime_item_ids_test.dart` + `test_realtime_purchase_payload.py`
- [x] Verified: `flutter analyze` (1 pre-existing `bid` warning), `trade_date_range_parity_test` + `realtime_item_ids_test` pass

**Manual QA (performance) — run before prod:**

| Check | Pass |
|-------|------|
| Home idle 60s: ≤6 API calls | [ ] |
| Open item: 3 calls (catalog + stock + activity), no full `trade-purchases` list | [ ] |
| Scroll purchase history: one `trade-purchases?catalog_item_id=` | [ ] |
| Two devices: staff patches item A; owner item B detail stable | [ ] |
| Shell tabs + redirects (`/stock/changes`, `/dashboard`, …) | [ ] |
| Staff scan → quick stock → save | [ ] |

**Deploy blockers (Phase 8):** Alembic `040` + `041` on production; Render health; owner + staff soak 15 min (no full-app refresh loop).

### V2 release gate (2026-05-29)

| Check | Pass |
|-------|------|
| P0 pytest delivery + stock + notifications (21 tests) | [x] 2026-05-29 |
| `flutter analyze` (touched surfaces) | [x] |
| Flutter unit tests (15: realtime, stock metrics, notifications, parity, cache) | [x] 2026-05-29 |
| Alembic head `042_catalog_stock_list_sort_index` (repo) | [x] |
| `flutter build web --release` → `flutter_app/build/web` | [x] 2026-05-29 |
| Shell: `ShellRealtimeListener` + `notificationCenterCoordinator` (owner + staff) | [x] |
| Alembic **040 + 041 + 042** on Supabase (MCP verified) | [x] |
| Render `DATABASE_URL` = same Supabase | [ ] confirm |
| Owner + staff **15 min soak** (no refresh loop) | [ ] manual |
| Delivery/stock validation checklist (roadmap) | [ ] manual |

### Screenshot fixes (May 29, 2026)

- [x] Owner home: error/skeleton states (no silent `SizedBox.shrink` on warehouse snapshot / OOS / pipeline errors)
- [x] Live bar: **N need attention** = out + low + critical (`homeStockAttentionCountProvider`)
- [x] Staff stock: `PHYS | PENDING` header/row; no SYSTEM column; fix “Physical” label in diff column
- [x] Deliveries: sectioned staff page (Dispatched / Arrived / Pending verification); `isDeliveryCommitted` = `stock_committed` only; `backfill_delivery_status.py`
- [x] Stock math: bulk print + public scan use `expected_system_qty`; list API exposes `public_token`
- [x] Staff home: My Tasks removed from home; Tasks header icon; zero-activity message; pending deliveries block; low-stock tool orange only when count > 0
- [x] Low stock: single tab row (scope in filter menu); one primary action per row + overflow menu
- [x] Bulk labels: simplified toolbar; single PDF up to 200 labels; PDF spacing + name sanitization; QR → `/scan/{public_token}`
- [x] Public scan route `/scan/:token` (no login)
- [ ] **Manual:** `alembic upgrade head` + `python -m scripts.backfill_delivery_status` on production
- [ ] **Manual QA:** owner home body loads; live bar count ≈ low-stock page; staff stock columns; deliveries sections; SUGAR stock on labels; QR scan in browser logged out

### Phase 5–7 — pruning / desktop / P2
- [x] FEATURE_PRUNING: settings workspace branding removed; deleted unrouted `low_stock_operations_page.dart`
- [x] **FEATURE_PRUNING_COMPLETE (2026-05-29):** removed `tenant_branding_provider`; `/get-started` → login; deleted `reports_item_bi_page` (route → catalog item); removed reports fullscreen BI launcher; staff nav **Home | Stock | Scan | Deliveries | Settings** (`/staff/deliveries`, `/staff/settings`); dead stock sheets / low-stock orphan pages already gone
- [x] FEATURE_PRUNING dead files removed: `reports_fullscreen_page`, `stock_compact_update_sheet`, `quick_stock_patch_sheet` (active stock UX: `update_stock_sheet` + `quick_stock_action_sheet` only)
- [ ] FEATURE_PRUNING backlog (post-v1): merge owner/staff shells into single `AppShell(role)`; reports inner TabBar → single scroll
- [ ] Broker UI: keep (purchase workflow); audit DB for `broker_id` usage before removal
- [x] DESKTOP_DESIGN_SPEC (2026-05-29): `kDesktopMin=1024`, shell extended rail + footer, owner home 2-col grid, stock/purchase/users master-detail, item detail 2-card row, reports KPI row; secondary: catalog 2-col grid, notifications 2-col cards, search list+preview, settings max-width 720, staff home 2-col, opening/low-stock max-width 1280; `flutter analyze` clean; desktop layout smoke tests
- [x] V2 execution plan (2026-05-29): P0 pytest 14 passed; `HomeDeliveryPipelineCard` after critical alerts; staff home activity before collapsed totals; `reorder_request` notifications + `/catalog/item/:id` deep link; `update_stock_sheet` + `HexaResponsiveSheetViewport`; stock row min 56dp; `stock_row_metrics_test` aligned to expected_system_qty
- [x] V2 Tasks 21–30 polish (2026-05-29): stock row 56dp; notification toggles wired; staff physical-only row; reports already on `CustomScrollView`
- [x] UIUX_DEEP_AUDIT (2026-05-29): single `Stock summary` card on item detail; removed duplicate delivery card; verification log only; stock list drops status chip row; low-stock tap → item detail; reports insights 5m keepAlive; delivery/diff colors in summary
- [x] UIUX build pass (2026-05-29): mobile item detail **Overview / Purchases / Activity** tabs (`NestedScrollView`); opening stock **pinned table header**; `flutter analyze` + build verify
 (FEATURE_PRUNING §8A backlog)

### Phase 8 — release
- [x] Supabase MCP: 2 unread notifications in DB
- [ ] Render MCP logs (workspace auth required)
- [ ] Manual QA owner + staff post-deploy

### Audit remediation (2026-05-30 plan)

| Phase | Status | Notes |
|-------|--------|-------|
| Sprint 1 — stock truth (backend movement, diff, idempotency, disputed slice) | [x] | `undo_last` → `apply_stock_movement`; `shortage` single-fetch; bulk suppliers in `list_stock` |
| Sprint 1 — Flutter invalidation (delivery paths, staff verify, realtime) | [x] | Staff home verify/arrive; `purchase.changed` already fans out via warehouse signal |
| Sprint 1 — tests | [x] | `test_physical_count_diff_sign.py`; `test_stock_undo` movement assert; `trade_list_api_status_test` |
| Sprint 2 — nav, filters, verify UX | [x] | Shell `PopScope`; API `pending` + legacy int; verify banner uses `needsStaffAction` |
| Sprint 2 — overlays + item tracking | [x] | `PartyInlineSuggestField` overlay default; item detail tracking strip |
| Sprint 3 — perf / DB | [x] | `list/compact`; Alembic `043` indexes; low-stock single `shortage` query |
| Sprint 4 — UX backlog | [x] | 72px stock rows; home resume 5m throttle; scroll restore; stock empty `FriendlyLoadError`; camera pause |
| Sprint 5 — security | [x] | `opening_stock_locked` enforced on `patch_stock_item`; admin SQL console N/A (removed) |

**Deploy:** `alembic upgrade head` through `043_audit_perf_indexes` on Render/Supabase before soak.

### Warehouse logic audit remediation (2026-05-29 plan)

| Bug / phase | Status | Notes |
|-------------|--------|-------|
| LOGIC-001 invalidation gaps | [x] | `invalidateAfterDeliveryCommit` / `invalidateAfterDeliveryVerify`; low-stock ops in `invalidateWarehouseSurfacesLight`; realtime throttle bypass when `affectedItemIds` set; backend publishes `stock.changed` per item on commit |
| LOGIC-002 verify vs commit UX | [x] | Quick action **COMMIT STOCK** (owner-only, `readyForOwnerCommit`); banner/snackbar copy: verify = counts submitted, commit = stock added |
| LOGIC-003 unit conversion flag | [x] | `needs_unit_setup` on `StockUpdateOut` + commit response when bag/kg conversion missing |
| LOGIC-004 expected qty + quick purchase | [x] | `compute_expected_system_qty` + stock list/public item include `quick_purchase` movements |
| LOGIC-005 near-zero reorder fallback | [x] | `stock_status`: `0 < cur < 1` + `reorder <= 0` → `low` |
| LOGIC-006 revert hardening | [x] | `revert_confirmed_purchase_stock` → `apply_stock_movement(delivery_revoke)` + idempotency keys; delivery PATCH revert unblocked |
| Tests | [x] | `test_warehouse_logic_fixes.py`; `delivery_invalidation_test.dart` |

**Manual smoke:** commit from purchase detail + history quick action; staff verify (no stock delta); second device stock tab within one realtime poll; item with staff quick purchase shows expected = opening + deliveries + quick.

### STOCK_LOGIC_DEEP_AUDIT closure (2026-05-28)

- [x] `expected_system_qty` + `system_stock_out_of_sync` on stock detail API; item snapshot shows expected vs system + out-of-sync warning
- [x] PO `commit-stock` writes `delivery_receive` stock_movements with `trade_purchase:{purchase_id}:{item_id}` idempotency
- [x] `purchase_delivery_stock_already_applied` checks movement keys + legacy adjustment log
- [x] Fix `set_opening_stock` → `get_stock_item` internal call (Query default bug)
- [x] Backfill script: `backend/scripts/backfill_purchase_stock_commit.py` (dry-run supported)
- [ ] Deploy Alembic `040` + `041` on production
- [ ] Manual QA: opening + delivered vs system mismatch banner; recompute / commit flows
- **Backlog (out of scope):** consumption/daily usage tracking; persisted `catalog_items.total_delivered_qty` columns

### Purchase delivery lifecycle (PURCHASE_FLOW_DEEP_AUDIT — 2026-05-28)
- [x] Backend: migration `041_purchase_delivery_extras`; `TradePurchaseOut.delivery_status` + transition endpoints; staff verify does not commit stock
- [x] Flutter: `DeliveryStatus` enum, icon badges, full delivery fields on `TradePurchase`, detail timeline + truck meta, role-gated arrive (staff-only), `HomePendingDeliveriesCard`, history filters (`delivery_dispatched` / `delivery_arrived` / `delivery_commit`)
- [x] Tests: `test_trade_purchase_delivery_pipeline.py` + updated stock increment/reversal tests (9 passed)
- [ ] Deploy: run Alembic `040` + `041` on production before release
- [ ] Manual QA: owner dispatch → staff arrive/verify → owner commit; staff cannot commit
- **Out of scope:** expense tracker (per product decision May 2026 — not in LOGIC_AND_FEATURES_SPEC rollout)

### LOGIC_AND_FEATURES_SPEC rollout (2026-05-29)
- [x] P1: Staff delivery filters; owner-only opening stock POST; manager read-only business profile; admin-only user mgmt
- [x] P2: Stock list uses movement `delivery_receive` for purchased; pending by `delivery_status`; expected system + spec diff on list API
- [x] P2 Flutter: 6-column stock row (wide owner); staff Phys/System/Diff focus
- [x] P3: Item delivery card; staff financial sections hidden; staff sticky physical-only
- [x] P4: Staff home tasks-first order; inline pending delivery cards
- [x] P5: Owner home section reorder; opening stock + OOS + owner tasks snapshot
- [x] P6: Per-type notification toggles in Settings
- [x] Build fix (2026-05-29): settings role gates, owner tasks snapshot, stock row/desktop pane, `_parse_period_dates` Query guard; `flutter analyze` clean; `test_staff_cannot_commit_stock` + `test_stock_list_columns` pass
- [x] Wire notification kind toggles into merged feed (`notificationPassesKindToggles` + Settings kinds incl. physical_reminder)
- [x] Notification triggers: `delivery_idle` hourly scan (2h+ dispatched); `physical_count_reminder` cron 18:00 IST (`scheduled_notification_jobs.py`)
- [x] Staff stock row: warehouse row shows Physical (+ Pending truck) only — no System/Diff for staff
- [ ] Manual QA + prod migrations 040/041

---

## Notifications blank-cards fix (2026-05-28)

- [x] P0: `NotificationAlertCard` — `IntrinsicHeight` wrapper so cards render in `ListView` (fixes “Showing 1 of 3” + TODAY header + blank list)
- [x] P0: `_buildGroupedNotificationTiles` fallback — flat list when date buckets empty but `visible` non-empty
- [x] P0: `showEmptyState` guard when server reloads with cached merged feed
- [x] Tests: `notification_alert_card_test.dart` ListView height test; `notification_badge_feed_parity_test.dart`; `pytest test_notifications.py` (5 passed)
- [x] DB verify (Supabase MCP): business `7411c8cf-514c-4f42-b25b-14ba86c0d547` has **2 unread** `stock_variance` rows (user kichu, May 24) — merged feed also adds warehouse synthetics (`wh_*`) for Critical tab
- [ ] Render MCP logs: workspace not authorized — re-run `list_logs` on API for `/notifications` 401 after workspace select
- [ ] Manual QA: owner + staff — All / Critical / Warehouse tabs after deploy; sign out/in if session stale

---

## UIUX-AUDIT closure (2026-05-28)

- [x] Design token pass: warning/profit color normalization on owner/staff/catalog alert surfaces
- [x] Stock + shell polish: `BOUGHT` header, low/critical border-only rows, Purchases nav label, contextual FAB hiding
- [x] Owner-home clarity: Stock status wording, period scope hint, low stock moved above activity, card-gap spacing
- [x] Staff-home polish: recent scans strip, equal-weight secondary actions, section subtitle readability
- [x] Notifications polish: “Showing X of Y”, critical-tab copy clarity, filter-category regression test update
- [x] Item-detail polish: physical warning cell, compact ledger action, section anchor chips
- [x] Inline errors: `SectionInlineError` + owner home low-stock/movement migration + warehouse async support

---

## PERFORMANCE-AUDIT rollout (2026-05-28)

- [x] Core invalidation refactor: tiered home polling + reduced dashboard fan-out refresh bursts
- [x] Provider cache pass: keepAlive TTL for high-cost home/stock autoDispose providers
- [x] Widget/rebuild efficiency pass: shell/home const + canonical stock-count invalidation path
- [x] Backend summary collapse: `/stock/warehouse/alerts-summary` endpoint + API client wiring
- [x] Route-family deep audit: owner/staff/stock/shared-route hotspots reviewed and patched
- [x] Full router coverage log: auth + owner + staff + stock + catalog + purchase + reports + settings route families reviewed with tab/subtab interaction pass
- [x] Validation + docs: targeted analyze/tests + `plando/PERFORMANCE_AUDIT.md` implemented map

---

## Warehouse UX overhaul (2026-05-28)

- [x] Notifications: `NotificationAlertCard`, staff delivery routes, `pur_*` dismiss, dedupe/cap low_stock, `triggered_by_name` API, home alerts from merged feed
- [x] Stock table: SYSTEM / BUY / PHYS / DIFF / PEND columns; row tap actions; removed icon column
- [x] Owner home: purchases card first + bold; warehouse snapshot second
- [x] Reports: 5 primary tabs + More sheet; AppBar subtitle
- [x] Receive: pending list 1/N, bags/qty summary; collapsible home activity feed
- [x] Item detail: stock snapshot cards; hide stock when edit mode; `GET stock/item` period fields
- [x] Low-stock category badge shows item count

## Low stock UX rebuild (2026-05-28)

- [x] Unified `LowStockDashboardPage` for `/stock/low-stock` and `/staff/low-stock` (replaces operations filter-chip UI)
- [x] Category tree: dual LOW/OUT badges, 5 tabs (incl. pending delivery), scoped search
- [x] Item tile: BAG/TIN/BOX/KG grid, stock progress, inform owner / reorder / stock update / receive
- [x] Data: `lowStockByCategoryProvider` includes critical + pending delivery rows
- [x] **Compact row UI** (`LowStockCompactItemRow`): stock · reorder · bought · pending + icon actions (less scroll)
- [x] Search row: inline scope icons + **subcategory filter** menu/chip; search matches item names in all scopes
- [x] Tab badges: red counts on icon tabs; PDF + CSV export from filtered view
- [x] Owner/staff home: red badge on Low stock quick action (owner grid + staff tools/quick links)

## Staff / stock / reports sprint (2026-05-28)

- [x] P0: 401 session expired + staff providers fail loud on auth errors
- [x] Staff home: tools top, low-stock attention (`staffLowStockAttentionCountProvider`), activity last, no home scan FAB
- [x] Stock table: ITEM / SYSTEM / PHYS / DIFF; row meta for opening + pending truck
- [x] Item detail: legacy STOCK ON HAND grid removed; `ItemDeliveryStatusCard` added
- [x] Reports: overview chart overlap fix; summary collapsed by default on mobile
- [x] Tests: `stock_row_metrics_test.dart`

---

## Warehouse home + notifications sprint (2026-05-28)

**Canonical docs:** [`plando/README.md`](plando/README.md)  
Checklist: [`plando/TODO_IMPLEMENTATION.md`](plando/TODO_IMPLEMENTATION.md)  
Patches: [`plando/IMPLEMENTATION_PATCHES.md`](plando/IMPLEMENTATION_PATCHES.md)

- [x] `plando/` audit pack (7 files + README + code-verified TODO corrections)
- [x] Cross-links from `docs/harisree/README.md` and `TASKS.md`
- [x] P0–P3 code (TODO-01…20) — home, notifications, stock summary API, performance
- [x] Staff home rebuild ([`plando/STAFF_HOME_REBUILD.md`](plando/STAFF_HOME_REBUILD.md)) — compact header, shift strip, tools grid, focus picker
- [x] Notifications gap closure ([`plando/NOTIFICATIONS_SYSTEM_AUDIT.md`](plando/NOTIFICATIONS_SYSTEM_AUDIT.md)) — role filter, compact empty, critical priority, no open flash
- [x] Phase B — stock table / item detail epic ([`plando/STOCK_SYSTEM_AUDIT.md`](plando/STOCK_SYSTEM_AUDIT.md)) — 30d history, ledger hint, PURCHASE null/0, list padding, pending delivery qty, opening-stock CTA

---

## LOW-STOCK-REBUILD (2026-05-27)

- [x] Backend: `GET low-stock/summary`, `GET low-stock/operations`, priority + lifecycle enrichment, `stock_dispute_cases` (039)
- [x] Flutter: `LowStockOperationsPage`, desktop 3-panel shell, bulk CSV export, lifecycle strip, context panel
- [x] Notifications: mismatch/delayed deep links; owner stock-audit approval sheet
- [x] Docs: `docs/harisree/LOW_STOCK_OPERATIONS_REBUILD.md`
- [x] Tests: `test_low_stock_operations.py`, `low_stock_snapshot_row_test.dart`

---

## Harisree Warehouse completion phases (2026-05-26)

Canonical phase doc: [`docs/harisree/IMPLEMENTATION_PHASES.md`](docs/harisree/IMPLEMENTATION_PHASES.md)

- [x] Phase 0 docs/tracker setup: ordered phase plan added to Harisree docs hub
- [x] Phase 1 cleanup: remove AI/voice/WhatsApp scheduling/cloud expense/Razorpay/billing/maintenance billing surfaces
- [x] Phase 2 delivery stock correctness: delivery confirmation updates stock once; revoke reverts
- [x] Phase 3 notifications: truthful unified badge + Stock/Purchases/System tabs
- [x] Phase 4 barcode speed + public QR item endpoint
- [x] Phase 5 PDF reliability: logo-safe, share/download/print feedback
- [x] Phase 6 stock physical/purchased/difference workflow
- [x] Phase 7 opening stock setup and lock/override rules
- [x] Phase 8 staff quick purchase logs + item purchase history
- [x] Phase 9 responsive desktop/mobile UX audit
- [x] Phase 10 performance: keep-alive providers, parallel calls, no double loading
- [x] Phase 11 Help & Guide + backup flow
- [x] Phase 12 sales comparison report

### Pending audit reconciliation (2026-05-26)

- [x] Section prompt md files reconciled through `dfiles/13_SALES_COMPARISON_REPORT.md`
- [x] Docs now state local Alembic head and partial/deferred scope for auto backup and sales comparison upload
- [ ] Cleanup audit: remove unwanted feature files still present outside active routes
- [x] Schema validation: local Alembic head and backend import pass; Supabase schema has 033-036 applied and `alembic_version = 036_staff_purchase_logs`
- [x] Feature gap decision: auto backup schedule/history explicitly deferred in `dfiles/12_AUTO_BACKUP.md`
- [x] Feature gap decision: PDF/XLSX sales comparison upload explicitly deferred in `dfiles/13_SALES_COMPARISON_REPORT.md`
- [x] Production QA automated pass: `flutter analyze`, `flutter build web`, backend pytest, Render health/ready, and Vercel smoke pass
- [ ] Manual release QA still needs a physical Android camera/PDF/offline/keyboard/sign-out pass before store/client handoff

### Deep SaaS audit build — Phase 1 hardening (2026-05-26)

- [x] Purchase history date filter: stop sending next-day `purchase_to`; backend already treats it as inclusive
- [x] Barcode parity: scanner accepts warehouse/retail linear formats; stock search matches saved `barcode`
- [x] Purchase write permissions: payments require `purchase_edit`; delivery stock changes require `stock_edit`; scan confirm/update require `purchase_create`
- [x] Staff delivery response redacts trade-purchase financial fields
- [x] Stock period and daily usage purchased quantities count delivered purchases only; pending orders remain separate metadata
- [x] Regression checks: `backend/tests/test_trade_purchases.py`, `flutter_app/test/trade_date_range_parity_test.dart`, targeted Flutter analyze

### Staff purchase + stock workflow rebuild (2026-05-26)

- [x] Backend stock movement ledger: `stock_movements`, idempotency keys, stock versioning, row-locked movement service
- [x] Quick purchase API: item-prefilled route with supplier/broker ids, staff purchase log relation, movement link, activity logging
- [x] Compact stock row actions: Physical Stock Update, Add Purchase Quantity, View Item Activity
- [x] Physical stock sheet: absolute count + reason + notes + stale stock protection
- [x] Purchase quantity sheet: supplier/broker autocomplete, idempotent submit, warehouse surface invalidation
- [x] Item activity: merged movements, quick purchases, and staff activity endpoint/provider plus operational detail tabs
- [x] Owner visibility: recent feed includes quick purchase entries and stock movement projections
- [x] Realtime sync: backend stock events + Flutter invalidation listener with polling fallback
- [x] Validation: `pytest backend/tests` printed `259 passed`; `flutter analyze`; `flutter test test/stock_row_actions_test.dart test/trade_date_range_parity_test.dart`

### Responsive UI/UX audit + fixes (2026-05-26)

- [x] Flutter responsive primitives: breakpoints, adaptive gutters, max-width containers, keyboard-safe sheet viewport, accessible filter chips
- [x] Shell/navigation: owner/staff bottom nav tap targets, compact FAB slot, responsive action sheet behavior
- [x] Operational core: home desktop max-width, stock row/filter responsiveness, stock sheets, item barcode/actions, barcode scanner, bulk barcode print toolbar/preview
- [x] Data screens: reports filter wraps, legacy analytics table scaling removal, purchase review mobile cards
- [x] Forms/overlays: item code, barcode, reorder, stock row action/preview/update/purchase sheets normalized to safe scrollable sheet viewport
- [x] Audit report: `docs/harisree/UI_UX_RESPONSIVE_AUDIT_2026-05-26.md`
- [x] Validation: `flutter analyze`; `flutter test test/responsive_layout_smoke_test.dart test/stock_row_actions_test.dart test/trade_date_range_parity_test.dart`

Verification gates per phase:
- Backend import/app tests, migration chain, stock SQL checks when relevant.
- Flutter `pub get`, targeted analyze/tests, full analyze before push.
- Business scenarios: purchase creation no stock change; delivery confirm adds; revoke reverts; opening stock initializes; physical count records; staff cash buy increments.

---

## Master Fix v3 — DB + §29 completion (2026-05-24)

- [x] Supabase MCP audit: critical columns present; `harisree_034_master_fix_v3_prod_parity` applied
- [x] Repo mirror: [`backend/sql/034_master_fix_v3_prod_parity.sql`](backend/sql/034_master_fix_v3_prod_parity.sql)
- [x] Stock alerts summary: `out_of_stock`, `missing_item_code`, `total_items`; chip counts via API
- [x] `update_stock_sheet` → `invalidateWarehouseSurfaces`
- [x] Stock search: instant local filter + API debounce
- [x] Bulk barcode PDF: cancellable progress dialog
- [x] Staff home: pending deliveries pill; staff low-stock: server notify + reorder sheet
- [x] Reports: View PDF full screen; quick view: in-sheet search → stock list
- [x] Home 5-min poll: low stock + warehouse alert providers

### §29 file audit checklist

| File | Status |
|------|--------|
| `purchase_entry_wizard_v2.dart` | Pass (keyboard, add-more, optional rates — verify on device) |
| `purchase_item_entry_sheet.dart` | Pass (onTapDown suggestions, keyboard-safe) |
| `catalog_add_item_page.dart` | Pass (add another, print label, pre-fill) |
| `staff_home_page.dart` | Pass (badges, pending delivery pill, logout app name) |
| `stock_page.dart` | Pass (sort recent, count chips, instant search) |
| `catalog_item_detail_page.dart` | Pass (reorder edit, hero stock; tabs remain) |
| `barcode_pdf_service.dart` | Pass (small labels, no price) |
| `splash_page.dart` | Pass (logo, gradient, Harisree Warehouse) |
| Notifications on stock patch | Pass (`stock_compact_update_sheet`) |

- [ ] Deploy Vercel + sign out/in after release

### Staff UX + bulk PDF (2026-05-24)
- [x] Bulk PDF: clamp label dims, skip FittedBox on tiny cells, per-label safe cells, infinity-friendly errors
- [x] Bulk print toolbar: compact chip row + action row (no stacked SegmentedButtons)
- [x] Bulk list: StockTableLayout rows, Ordered/Stock columns, truck on pending qty
- [x] Printable-only filter before PDF (skip items without barcode/code)
- [x] Staff home: 3-col quick grid, horizontal activity chips, compact scan CTA
- [x] Receive shipment: `/staff/receive` list + `/staff/receive/:id` checklist + mark delivered
- [ ] Push + Vercel redeploy (web title + bulk PDF fixes)

### Low stock + alerts parity (2026-05-24)
- [x] `lowStockByCategoryProvider`: merge API `low` + `out` pages (was low-only → empty while Stock showed 534 out)
- [x] Low stock tabs: **Purchased** (period qty or pending order, still low/out)
- [x] Alert tap → `/stock/low-stock` or `/staff/low-stock` (not generic stock list)
- [x] `StockNumberDisplay`: bold unit label, red low / orange out
- [x] Bulk PDF web sheet: **Download all N PDFs** (staggered; per-part still available)
- [x] Owner home quick action: **Add item** → `/catalog/quick-add`
- [ ] Full app page-by-page QA (filters, suggestions scroll, 401 cloud businesses on stale session)

---

## Harisree Warehouse Master Fix v3 (2026-05-24)

### Wave 1 — Branding & splash (§1–3)
- [x] Full package rename `harisree_warehouse` + import sweep
- [x] App name Harisree Warehouse (pubspec, Android, iOS, web manifest)
- [x] Splash animated logo + brand gradient
- [x] HexaColors app name constants + `StockNumberDisplay` widget

### Wave 2 — Typography & purchase flow (§3–5)
- [x] Global typography / spacing tokens in touched UI
- [x] Purchase item creation flow fixes (wizard + sheets)
- [x] Supplier/category pre-fill on add-more

### Wave 3 — Keyboard & suggestions (§6–7)
- [x] Keyboard-safe sheets on key entry pages
- [x] Suggestion dropdown tap/scroll fixes

### Wave 4 — Stock list & status (§8–9)
- [x] Stock sort recent / latest updated top
- [x] Status colors, bag numbers, bold tags on rows

### Wave 5 — Low stock & reorder (§10–16)
- [x] Owner low-stock category tree
- [x] Staff low-stock + reorder level display
- [x] Reorder level per item (detail + API)
- [x] Pending delivery / truck icon (`has_pending_order`, `pending_order_days`)
- [x] Staff dashboard tabs & badges
- [x] Staff purchase history tabs
- [x] Low-stock local notifications on patch

### Wave 6 — Barcode PDF & reports PDF (§17–19, §21)
- [x] Bulk barcode: small thermal only; PDF errors 6s snackbar
- [x] Small label layout: barcode left, name/date/qty right; no price/unit text
- [x] Supplier/broker/reports PDF bold names + qty with units
- [x] Reports category/subcategory drill: bold items, qty+units

### Wave 7 — Item detail & auth (§20, §26–28)
- [x] Catalog item detail hero stock card + StockNumberDisplay
- [x] Reorder level edit dialog (existing API)
- [x] `item_quick_view_sheet.dart` DraggableScrollableSheet
- [x] Barcode print `preloadItemId` query + route
- [x] Login prominent biometric when `BiometricLogin.isAvailable`

### Wave 8 — Sync & errors (§22, §24, §29)
- [x] Invalidate warehouse providers after stock patch & catalog add
- [x] Error snackbars 6s on bulk barcode PDF paths
- [x] Backend stock list pending-order fields (undelivered purchases join)
- [x] Full §29 file audit — waves 1–8 implemented; deploy QA on Vercel

---

## Stock warehouse rebuild (2026-05-27)

- [x] Operational top bar: Back, Stock, History, Filter, Search, More (period in filter sheet only)
- [x] Hidden search until icon; compact horizontal chips (All/Low/Out/Missing Code/Missing Barcode)
- [x] Table **ITEM | PURCHASE | STOCK | DIFF** — inline status under stock; row quick-action icons
- [x] Backend `warehouse_diff_qty` = period purchased − physical; staff quick purchases in period map
- [x] `physical-update` upserts `stock_physical_counts` for list physical/diff columns
- [x] Desktop ≥1100px: list + `StockDesktopDetailPane` with activity preview
- [x] Tests: `test_stock_list_columns.py`, `responsive_layout_smoke_test` (`StockWarehouseRow`)

## Stock warehouse rebuild (2026-05-24) — superseded by 2026-05-27 table above

- [x] Compact top nav: period dropdown + filter + search toggle (no TabBar)
- [x] Sticky collapsible search row; warehouse filter sheet (subcategory, status, unit, missing flags)
- [x] Table layout **ITEM | STOCK | STATUS** with bordered rows (`stock_table_row.dart`)
- [x] Row tap → compact update sheet (Physical/Sale/Damage/Correction); default period **All time**
- [x] Changes on separate route `/stock/changes` and `/staff/stock/changes`
- [x] Staff: no purchased/diff columns; owner metadata footer (diff, updated by)
- [x] Widget tests: `stock_status_badge_test.dart`

## Stock / staff UX overhaul (2026-05-23)

- [x] Stock list **page merge** + Prev/Next footer; `Showing N of total` (fixes load-more replacing rows)
- [x] Search: API `q=` only, **clear (X)**, no initState `q` wipe
- [x] Inline **category + subcategory** autocomplete on All tab; **Clear filters**
- [x] Bordered table rows + shared column header (`stock_table_layout.dart`)
- [x] Staff home **Warehouse stock** card (bags/kg/boxes/tins on-hand) → subcategory sheet → `/staff/stock`
- [x] Quick add **Basics | Unit & codes | Review** tabs
- [x] Stock movement page: `stockPagePeriodProvider` + error retry
- [x] Network: QUIC/`ERR_NETWORK_CHANGED` retry, session-expired banner, web bulk list 100/page
- [x] **NETWORK_DEEP_AUDIT (2026-05-29):** `stockListCacheProvider` (30s family dedupe); home OOS uses scoped query; staff low → `listStockLow`; shell `ShellRealtimeListener` (owner+staff); notifications list 120s keepAlive + off-home poll 120s; warehouse alerts 60s cache; delivery `purchase_arrive` offline queue + sync; Alembic **042** stock-list sort index
- [ ] Deploy Vercel + sign out/in after release
- [ ] **Prod DB:** Alembic **040 + 041 + 042** (delivery + catalog sort index) — manual after review

---

## Unit normalization + stock reconciliation (2026-05-23)

- [x] Backend SSOT: `unit_normalization.py` — `default_unit` wins over AI `stock_unit`; kg→bag via `default_kg_per_bag`
- [x] Period purchased sum uses normalized lines (not raw `SUM(qty)`)
- [x] Stock apply/revert/diff on confirm uses normalized qty
- [x] API: `ledger_variance_qty`, `period_usage_qty`, `qty_in_stock_unit` on recent purchases, `current_stock_kg`
- [x] Migration `backend/sql/033_trade_line_qty_in_stock_unit.sql` + backfill/repair scripts
- [x] Flutter dual display (BAG + kg subtitle) on stock row, preview, item detail, intelligence
- [x] `invalidatePurchaseWorkspace` → `invalidateWarehouseSurfaces` for realtime stock refresh
- [x] **Prod (Supabase MCP 2026-05-23):** migration `trade_line_qty_in_stock_unit`, `fix_prod_catalog_unit_profiles.sql`, SQL backfill 96/109 lines (`qty_in_stock_unit`); 13 edge unit mismatches remain (runtime normalize)

## Smart unit engine V2 (2026-05-23)

- [x] `stock_tracking_profile.py` — wholesale bag vs retail packet vs loose kg (ATTA 5KG → piece, SUGAR 50KG → bag)
- [x] Purchase line unit validation blocks bag on retail packet / piece on wholesale bag
- [x] Catalog create: `piece` + `default_kg_per_bag` → `RETAIL_PACKET` + verified profile
- [x] Flutter: `PackagingTypeSelector` on add-item; `detectUnitFromName` no longer maps all `*KG` to bag
- [x] Item detail: Unit engine panel (display unit, packaging, weight)
- [ ] Re-tag existing production items with wrong `package_type` (audit `data/products_categories_items/Products list.xlsx` vs DB)

### Unit engine UX rollout (pages)

- [x] Add item: packaging type picker + labels + autofill kg from name
- [x] Item detail + stock intelligence: `UnitEngineSummaryCard`
- [x] Stock list row: subcategory-only line (no duplicate category trail)
- [x] Purchase line sheet: block wrong unit before save (client + API)
- [x] Quick stock patch: `opening_stock` reason chip
- [x] Stock UX: All time period, server purchased filter, full-screen stock (no bottom nav), purchase stats + contacts row on home
- [ ] Quick add / batch create: same packaging picker
- [ ] Staff home / barcode create: packaging picker
- [ ] Seed script from `data/files/products_by_category_seed.json`

---

## Screenshot UX fixes (2026-05-23)

- [x] Stock row: **Buy / Now / Δ** numeric columns (no `150 bags` suffix); no horizontal scroll
- [x] Bulk print: same qty columns; **100-label cap** before PDF; **Download** opens PDF preview page with app-bar download
- [x] Bulk print: **A4 splits by 30/40/50/60 labels per PDF file** (web-safe); **30/40/50/60 per page** inside each file; thermal splits multi-PDF; footer **stock + last purchase**; scan **Update stock**; auth/offline errors on label fetch
- [x] Bulk print: fix **`Infinity.toInt()`** PDF crash (sanitize qty); auto **A4 + Code128 + 50/file** when selection > 25
- [x] Staff search: catalog item → **item detail** (history, ledger, purchases); purchase bills visible; staff bill → `/staff/purchase-history/:id`
- [x] Search PO lines: qty numbers only (no bag/kg); PUR id bold primary
- [x] Item detail stock panel: purchased/moved period numbers without unit suffix

## Stock / Home data fix (2026-05-23)

- [x] Home **Warehouse Stock Overview** uses `stockOnHandTotalsProvider` (physical on-hand), not purchase-period totals
- [x] Stock search debounces to API `q=` (finds SUGAR etc. beyond first 50 rows)
- [x] Stock table headers: **Purchased | Stock | Diff**; Diff = physical − purchased in period
- [x] Purchased filter: sort by highest period purchase qty first
- [x] 401 session: logout on failed refresh; degraded banner + Home session hint (not fake ₹0)
- [x] Reports/Home breakdown rows: bags · boxes · tins · kg subtitle when API sends unit totals
- [x] Warehouse analytics Items tab: fallback slices from category top items when `itemSlices` empty

## Stock Page UX V8 (2026-05-23)

- [x] Stale-while-revalidate stock list (no full-page skeleton on filter/period change)
- [x] Column header sliver + row preview sheet + PENDING badge + purchased line
- [x] Filter: subcategory `Autocomplete`, supplier `SearchPickerSheet`, purchased-in-period toggle
- [x] Backend: `sort=recent` by `last_purchase_at`; list fields `last_purchase_human_id` / `last_purchase_delivered`
- [x] Stock list bottom padding for bottom nav; filter sheet inset
- [x] Header **Purchased** chip + reload progress bar

---

**Last updated:** 2026-05-23 (Production audit P0 fixes)

---

## Production audit P0 (2026-05-23)

- [x] Stock revert on cancel/delete confirmed purchase (`stock_inventory.py`, `trade_purchase_service.py`)
- [x] Stock diff when editing confirmed purchase (qty change 10→8)
- [x] RBAC: `purchase_create` / `purchase_edit` on trade routes; `export_access`; `analytics_access`; `stock_edit` on usage submit
- [x] Flutter: friendly errors (duplicates, daily usage, audit session); staff activity hides totals; barcode PDF `hideFinancials` for staff; 408/429 copy
- [x] Tests: `test_purchase_stock_reversal.py` (2 tests pass)
- [ ] P1: atomic stock SQL / idempotency keys / staff home missing-code server endpoint / concurrent race tests

---

## StockEase V7 — Master Plan Checklist

**Order:** HIDDEN-CRITICAL → SEARCH-FIX → UX-* → NEW-PAGES → FEATURES → GUARDS.

### HIDDEN CRITICAL

- [x] HIDDEN-01 unit_utils float tolerance (verify)
- [x] HIDDEN-02 stock search local filter (verify)
- [x] HIDDEN-03 stockTotalsProvider period + backend dates
- [x] HIDDEN-04 staffTodaySummaryProvider audit/summary endpoint
- [x] HIDDEN-05 quick_stock_patch reason + qty (verify)
- [x] HIDDEN-06 stock search toggle clears local query (N/A — inline search field)
- [x] HIDDEN-07 home 5min light poll (not 30s full invalidate)
- [x] HIDDEN-08 barcode invalidation after patch (verify)
- [x] HIDDEN-09 purchase save full provider invalidation
- [x] HIDDEN-10 home/reports appSelectedPeriodProvider sync
- [x] HIDDEN-11 notifications empty section headers
- [x] HIDDEN-12 settings maintenance owner-only (verify)
- [x] HIDDEN-13 staff stock-first search + keyboard focus
- [x] HIDDEN-14 owner bottom nav Purchase FAB (+ opens /purchase/new)

### SEARCH REFRESH FIX

- [x] SEARCH-01 stock local filter (verify)
- [x] SEARCH-02 catalog local filter (verify)
- [x] SEARCH-03 purchase home local filter (verify)
- [x] SEARCH-04 reports items local filter (verify)
- [x] SEARCH-05 barcode manual search local (verify)
- [x] SEARCH-06 contacts local filter (verify)

### STOCK / HOME / REPORTS / STAFF / CATALOG / PURCHASE / BARCODE UX

- [x] STOCK-UX-02 filter header 2 rows + bottom sheet (V6 baseline)
- [x] STOCK-UX-03 row action menu complete (V6 baseline)
- [x] HOME-UX-02 recent changes 8s timeout + icons (V6 baseline)
- [x] REPORTS-UX-02/03/04 single card + donut + tabs (V6 baseline)
- [x] STAFF-UX-01 full staff home layout (V6 baseline)
- [x] STAFF-UX-04 checklist optimistic + progress (V6 baseline)
- [x] CATALOG-UX-01–04 tabs, overview, pagination, duplicate warn (V6 baseline)
- [x] PURCHASE-UX-01/02 stock in suggestions, all units (V6 baseline)
- [x] BARCODE-UX-02/03/04 batch 100, footer, days colors (V6 baseline)

### NEW PAGES

- [x] NEW-PAGE-01 item timeline `/catalog/item/:id/timeline`
- [x] NEW-PAGE-02 stock audit summary rebuild
- [x] NEW-PAGE-03 stock movement `/stock/movement`
- [x] NEW-PAGE-04 reorder suggestions `/stock/reorder-suggestions`
- [x] NEW-PAGE-05 reports PDF download polish (V6 baseline)
- [x] NEW-PAGE-06 catalog owner bulk/sort/filter (V6 catalog baseline)

### NEW FEATURES & GUARDS

- [x] FEAT-001 keep-alive 10 min (verify)
- [x] FEAT-002 growth comparison strip (verify)
- [x] FEAT-004 AI usage page owner-only
- [x] GUARD-01 duplicate purchase dialog (V6 backend 409 flow)
- [x] GUARD-02 item name similarity warning (V6 catalog create)
- [x] GUARD-03 negative stock warning
- [x] GUARD-04 barcode conflict check

### Verification

- [x] V7-SMOKE 25-item smoke checklist (code paths; manual QA on device)
- [x] V7-ANALYZE flutter analyze clean on touched files
- [x] V7-PYTEST backend tests pass (stock increment; full suite run separately)
- [x] V7-DEDUPE removed duplicate home 5min full-refresh timer; purchase save uses single invalidatePurchaseWorkspace path

---

## StockEase V6 — Master Plan Checklist

**Order:** CRITICAL → SEARCH-FIX → STOCK-PAGE-UX → HOME-PAGE-UX → REPORTS-UX → STAFF-UX → CATALOG-UX → PURCHASE-UX → BARCODE-UX → NEW-FEATURES.

### Setup

- [x] RULES-001 update `.cursor/rules/stockease.mdc` to V6

### CRITICAL

- [x] CRITICAL-01 unit utils / display helpers: no `101.000 bag`
- [x] CRITICAL-02 purchase rate display: no `₹—` when fallback is computable
- [x] CRITICAL-03 purchase save invalidates stock/home/catalog caches
- [x] CRITICAL-04 app period provider alignment across Home/Reports/totals
- [x] CRITICAL-05 bulk barcode print chunks at 100 labels
- [x] CRITICAL-06 barcode label footer date · qty · supplier
- [x] CRITICAL-07 maintenance/UPI hidden from non-owner roles
- [x] CRITICAL-08 staff home stats from today stock/audit work

### SEARCH REFRESH FIX

- [x] SEARCH-01 stock page local filter; no API call on keystroke
- [x] SEARCH-02 catalog page local filter
- [x] SEARCH-03 purchase home local filter
- [x] SEARCH-04 reports items local filter
- [x] SEARCH-05 barcode manual search local filter
- [x] SEARCH-06 contacts/supplier search local filter

### STOCK PAGE UX

- [x] STOCK-UX-01 stock row story layout
- [x] STOCK-UX-02 stock filter header summary strip
- [x] STOCK-UX-03 stock row action menu
- [x] STOCK-UX-04 quick stock patch qty input + reason chips

### HOME PAGE UX

- [x] HOME-UX-01 stats card 24pt colored numbers
- [x] HOME-UX-02 recent changes skeleton/empty/icon/typography
- [x] HOME-UX-03 movement rows hide zero values
- [x] HOME-UX-04 low stock Order action
- [x] HOME-UX-05 six clear quick actions

### REPORTS UX

- [x] REPORTS-UX-01 period filter updates range/data
- [x] REPORTS-UX-02 remove duplicate/collapsible total card behavior
- [x] REPORTS-UX-03 donut center text fix
- [x] REPORTS-UX-04 reports tabs labels/scroll alignment

### STAFF UX

- [x] STAFF-UX-01 staff home stats/actions/recent/low-stock layout
- [x] STAFF-UX-02 staff search icon focuses stock search
- [x] STAFF-UX-03 shell back buttons use `context.pop()`
- [x] STAFF-UX-04 checklist optimistic update + progress
- [x] STAFF-UX-05 keyboard-safe staff suggestions/forms

### CATALOG & ITEM DETAIL UX

- [x] CATALOG-UX-01 item detail scrollable tabs / label download fallback
- [x] CATALOG-UX-02 item overview full-story layout
- [x] CATALOG-UX-03 purchase history pagination
- [x] CATALOG-UX-04 duplicate item create warning

### PURCHASE ENTRY UX

- [x] PURCHASE-UX-01 item suggestions show current stock clearly
- [x] PURCHASE-UX-02 quick add supports box/tin units

### BARCODE & SCAN UX

- [x] BARCODE-UX-01 after scan update refresh + confirmation
- [x] BARCODE-UX-02 reorder list supplier/rate + Order button
- [x] BARCODE-UX-03 days signal color + tooltip

### NEW FEATURES

- [x] FEAT-001 keep-alive ping every 10 minutes
- [x] FEAT-002 reports PDF statement confirmation/download polish
- [x] FEAT-003 stock row subtitle shows bought today
- [x] FEAT-004 home growth comparison strip
- [x] FEAT-005 item change timeline
- [x] FEAT-006 notifications filters + unread indicator polish

### Infrastructure / Manual

- [x] INFRA-001 Render Starter upgrade noted, not coded
- [ ] INFRA-002 Verify APScheduler low-stock push alert at 8am

---

## StockEase V5 — Master Cursor Prompt Checklist

**Order:** P0 → Business Logic → P1 → P2 → Features. Do not edit prompt/plan files; this section tracks implementation without replacing history below.

### Setup

- [x] RULES-001 create `.cursor/rules/stockease.mdc`

### P0 — Fix immediately (core broken, data wrong)

- [x] BUG-001 bulk barcode print: chunk 100 labels, no crash on 533 items
- [x] BUG-002 daily usage: flexible `lines/items/usage_lines/data` parsing + empty state
- [x] BUG-003 notifications: empty list + no orphan section headers + title `Notifications`
- [x] BUG-004 unit utils: near-integer tolerance for quantities
- [x] BUG-005 purchase rate display: no `₹—` when line total / qty is computable
- [x] BUG-006 recent changes: no permanent skeleton; wide range/timeout + dedupe
- [x] BUG-007 barcode PDF labels: footer date · qty · supplier
- [x] BUG-008 staff checklist: optimistic complete + persisted progress
- [x] BUG-009 catalog item detail: web print fallback as `Download label PDF`
- [x] BUG-010 stock row: `NO BARCODE` inline chip, max 3 columns
- [x] BUG-011 recent changes: duplicate purchase entries removed
- [x] BUG-012 quick stock patch: direct qty input + Set button
- [x] BUG-013 settings: maintenance/UPI hidden from non-owner roles

### Business Logic — Silent Failures

- [x] BLOGIC-01 staff home summary from stock audit/today summary
- [x] BLOGIC-02 home period stats change with selected period
- [x] BLOGIC-03 purchase history pagination for large item histories
- [x] BLOGIC-04 bag/kg display consistent across views
- [x] BLOGIC-05 duplicate item check on catalog create
- [x] BLOGIC-06 stock update reason chips + audit type mapping
- [x] BLOGIC-07 barcode scan invalidates stock caches after update
- [x] BLOGIC-08 reports and home period sync via shared provider
- [x] BLOGIC-09 missing codes sorted by current stock descending
- [x] BLOGIC-10 purchase save updates stock and invalidates stock/home caches

### P1 — UX Broken / Wrong Data

- [x] BUG-014 reports period filter updates data and header range
- [x] BUG-015 reports page shows one summary card, not duplicate totals
- [x] BUG-016 reports donut center avoids truncated text
- [x] BUG-017 staff home search icon navigates/opens stock search
- [x] BUG-018 staff sub-page back buttons use `context.pop()`
- [x] BUG-019 home movement rows hide zero/no-data rows
- [x] BUG-020 user profile tabs scroll + permission labels sentence case
- [x] BUG-021 stock filters consolidated to search row + period/filter row
- [x] BUG-022 home stats card uses large bold colored numbers
- [x] BUG-023 purchase item search suggestions show current stock
- [x] BUG-024 quick add item offers box/tin unit options
- [x] BUG-025 reports `More` tab/chip renamed to `Items`
- [x] BUG-026 reports Match Home label shows current period
- [x] BUG-027 catalog item detail tabs scroll
- [x] BUG-028 reorder list includes supplier/rate + quick Order button
- [x] BUG-029 font sizes normalized in listed pages

### P2 — Improvements

- [x] BUG-030 search results exact/prefix matches first
- [x] BUG-031 stock days display tooltip + color coding
- [x] BUG-032 home recent changes event-type icons
- [x] BUG-033 staff keyboard-safe autocomplete/search forms

### Features

- [x] FEAT-001 keep-alive ping every 10 minutes
- [x] FEAT-002 PDF purchase statement download/export
- [x] FEAT-003 stock list shows purchased today

### Infrastructure / Manual

- [x] INFRA-001 Render Starter upgrade noted, not coded
- [ ] INFRA-002 Verify APScheduler low-stock push alert at 8am

---

## Sprint 24 — V4 master backlog (StockEase)

**Order:** BLOGIC → P0 gaps → P1 → P2 → Features. Sprint 23 IDs differ from V4 numbering (see note below).

### Business logic (silent failures)

| ID | Status | Summary |
|----|--------|---------|
| BLOGIC-01 | Done | Staff home today stats from stock audit feed + activity log |
| BLOGIC-02 | Done | Home totals card hides zero movement; period from dashboard |
| BLOGIC-03 | Done | Purchase history load-more verified (existing) |
| BLOGIC-04 | Done | Bag/kg/bag line on stock row + unit_utils |
| BLOGIC-05 | Done | Quick-add duplicate fuzzy dialog |
| BLOGIC-06 | Done | Quick stock patch reason chips + adjustment types |
| BLOGIC-07 | Done | Barcode scan invalidates stock after patch |
| BLOGIC-08 | Done | `app_period_provider` + home period sync listener |
| BLOGIC-09 | Done | Invalidate trade/catalog after barcode/code assign |
| BLOGIC-10 | Done | Missing codes page sort by stock desc |

### P0 gaps (V4 numbering)

| ID | Status | Summary |
|----|--------|---------|
| BUG-003 | Done | Notifications section headers only when group non-empty |
| BUG-008 | Done | Checklist optimistic complete + done/total progress |
| BUG-009 | Done | Catalog detail routes to barcode print (web download there) |
| BUG-012 | Done | Quick patch absolute qty field + Set |

### P1 / P2 / Features (V4)

| Area | Status | Summary |
|------|--------|---------|
| Reports | Done | Deduped summary card; “Items” more chip; PDF export existing |
| Stock chrome | Done | Row1 search + row2 period + Filters; status in sheet |
| Staff/misc | Done | Checklist tabs scrollable; notifications headers |
| P2 | Done | Days-since chip; reorder Order CTA; fuzzy prefix sort |
| FEAT-004/005 | Done | Period sync; reports PDF export (existing) |
| FEAT-006 | Done | Merged with BLOGIC-05 duplicate dialog |

**Sprint 23 → V4 map:** Sprint BUG-012/013 were notifications/filter; V4 BUG-012 = quick patch qty, V4 BUG-013 = settings owner (Sprint BUG-020).

---

## Sprint 23 — Screenshot bug fix (May 23)

| ID | Status | Summary |
|----|--------|---------|
| BUG-001 | Done | Bulk print batches of 100 labels |
| BUG-002 | Done | Daily usage empty state + flexible `lines` key |
| BUG-003 | Done | Notifications grouped list empty guard |
| BUG-004 | Done | `_fmtQty` near-integer tolerance |
| BUG-005 | Done | Purchase rate fallback from line total |
| BUG-006 | Done | Home recent feed 15s timeout + purchase dedupe |
| BUG-007 | Done | Label PDF footer date/qty/supplier |
| BUG-008 / BUG-018 | Done | Checklist % + tap complete + low-stock hints |
| BUG-009 | Done | Web download label PDF |
| BUG-010 | Done | Stock row NO BARCODE inline chip |
| BUG-011 | Done | (same as BUG-006 dedupe) |
| BUG-012 | Done | Notifications AppBar title |
| BUG-013 | Done | Filter sheet keyboard inset padding |
| BUG-014 | Done | Permission labels title case |
| BUG-015 | Done | Reports ring / pie center labels |
| BUG-016 | Done | Quick-add BOX/TIN chips |
| BUG-017 | Done | Warehouse scan +/- on counted qty |
| BUG-019 | Done | Home movement omits empty Sold/Transferred |
| BUG-020 | Done | Maintenance payment owner-only |
| BUG-021 | Done | Shorter report tab labels |
| BUG-022 | Done | Stock unit filters in filter sheet |
| BUG-023 | Done | Item ledger chips scroll horizontally |
| BUG-024 | Done | Recent changes icons by activity kind |
| BUG-025 | Done | Stock search prefix-first sort |
| BUG-026 | Done | User profile scrollable TabBar |
| BUG-027 | Done | Missing labels sort by stock desc |
| BUG-028 | Done | HexaDsType in touched sprint files |
| FEAT-001 | Done | Purchase picker stock hint in subtitle |
| FEAT-002 | Done | Update stock reason chips (Sale, Return, …) |
| FEAT-003 | Done | Reports “Match Home (Period)” dynamic label |
| FEAT-004 | Done | Home stock totals typography |
| FEAT-005 | Done | Reorder row supplier + last rate + mark ordered |
| INFRA | Done | Health keep-alive 10 min (`api_warmup.dart`) |

**Deploy note:** No new migration required for sprint 23 (optional `supplier_name` on barcode label API is additive).

---

# Purchase Assistant — Living task board (history)

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
| PO-DETAIL-REBUILD | P0 | Done | PO detail: pdf locale + export service, action bar, compact layout, desktop split, `PO_SUPPLIER_DD_MMM_YYYY` filenames — see `docs/harisree/PURCHASE_ORDER_DETAIL_REBUILD.md` |
| NOTIF-REBUILD | P0 | Done | Notifications: unified badge/feed, emitter + v2 schema, alert cards, filters, realtime invalidation — see `docs/harisree/NOTIFICATION_ALERT_SYSTEM.md` |
| OWNER-DASH-REBUILD | P0 | Done | Owner/admin home: purchase-first layout, critical alerts grid, purchase center, warehouse health, activity feed, staff panel, sticky period, role gate — see `docs/harisree/OWNER_DASHBOARD_REBUILD.md` |
| ITEM-DETAIL-REBUILD | P0 | Done | Item detail: enterprise control screen (snapshot, ledger, purchase cards, supplier intel, verification, export) + desktop split + router swap — see `docs/harisree/ITEM_DETAIL_REBUILD.md` |
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

## Opening Stock Setup Page — Operational Rebuild (2026-05-27)

- [x] Backend: `GET /stock/opening/setup` paginated summary + filters
- [x] Backend: `POST /{item_id}/opening-stock` uses `apply_stock_movement(opening_stock)`, enforces `reason` on locked qty changes, publishes `stock.changed`
- [x] Flutter: rebuilt opening-stock page (top bar, summary bar, search, filter chips, bordered table, set sheet, row actions, progress + filter sheets)
- [x] Catalog item detail: `_ItemWarehouseHeroHeader` now shows opening/current/diff/last stock update and deep-links to `/stock/opening-setup`
- [x] Bulk (P1): multi-select opening rows + bulk “Set opening qty” sequential apply; missing barcode warning navigates to `/stock/missing-barcodes`
- [x] Tests/docs: backend test suite passes + responsive widget overflow guard updated + docs created in `docs/harisree/OPENING_STOCK_SETUP_REBUILD.md`

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

## UI/UX audit remediation (May 30)

| ID | Status | Summary |
|----|--------|---------|
| UX-001 | Done | Migrated remaining sheets off `DraggableScrollableSheet` → `showHexaBottomSheet` / bounded `Column` |
| UX-002 | Done | Dense stock row: owner STOCK+status; staff PHYS only; 72px max |
| UX-003 | Done | `keyboard_aware_suggestion_overlay` uses root overlay |
| UX-004 | Done | Stock TabBar visible (List / Changes / Movement / Today) |
| UX-005 | Done | `stockListScrollOffsetProvider` + `PageStorageKey` scroll restore |
| UX-006 | Done | Reports primary chips: Overview · Items · Purchase · Activity |
| UX-007 | Done | Delivery status stripe helpers + purchase history tiles |
| UX-008 | Done | Shared `formatStockQtyNumber` in feeds/reports/purchase entry |
| UX-009 | Done | `HexaEmptyState` on stock, low-stock, purchase, reports, home activity, notifications |
| UX-010 | Done | Owner home compact: alert strip, 2×2 KPI grid (96px), lists capped |
| UX-011 | Done | Activity feed parses "Purchase received" → delivery committed + purchase route |
| UX-012 | Done | Confirm dialog before commit-stock; revert already confirmed |
| UX-013 | Done | Barcode scan debounce 300ms; camera stops on inactive |
| UX-014 | Done | Low-stock filter sheet sticky Apply + viewInsets |
| UX-015 | Done | Purchase history filters sticky Apply |

---

## Agent rules (short)

- One living doc: this file + `docs/harisree/`.
- No raw `DioException` in UI — `HexaErrorCard` / `FriendlyLoadError`.
- `ref.listen` + `setState` → `addPostFrameCallback`.
- Category chips → `Wrap`.
- Financial totals on backend only.
