# TODO IMPLEMENTATION
## Harisree Warehouse ERP · Strict Priority Order for Cursor

> Every item below is based on actual code evidence.
> No guesses. File paths and line descriptions are real.
> Implement in exact order — P0 first, P3 last.

---

## Status (2026-05-28)

P0–P3 implemented in codebase. Phase B (stock table / item detail epic) remains backlog in `STOCK_SYSTEM_AUDIT.md`.

---

## P0 — CRITICAL DATA / BUG FIXES (Do Today)

### TODO-01: Fix `All (5)` stock filter chip count
**Files:** `backend/app/routers/stock.py` (`stock_alerts_summary`), `flutter_app/lib/core/providers/stock_providers.dart` (`stockStatusCountsProvider`), `flutter_app/lib/features/stock/presentation/widgets/stock_status_chip_row.dart`
**Problem:** Chip `All (5)` is wrong while `Out (567)` is high. UI reads counts from `stockStatusCountsProvider` → `GET /stock/alerts/summary`. Backend sets `total_items` to count of items with `current_stock > 0` (**active only**), not full catalog.
**Fix:**
1. Backend: `total_items` = count of all non-deleted catalog items.
2. Optional: add `active_out_of_stock` for TODO-20; map `out` chip to that when present.
3. Flutter: keep `listStock()['total']` fallback in `stockStatusCountsProvider`.
**Risk:** Low. Display + summary API.

### TODO-02: Delete duplicate `_OpeningStockSetupBanner`
**File:** `home_page.dart`
**Problem:** `_OpeningStockSetupBanner` and `HomeCriticalAlertsGrid` both show opening stock alert.
**Fix:** Remove the entire `_OpeningStockSetupBanner` class and its usage in `home_page.dart`.
`HomeCriticalAlertsGrid` already handles this from `warehouseAlertsProvider`.
**Risk:** None. `HomeCriticalAlertsGrid` covers it.

### TODO-03: Fix warehouse alert notification read state — **Done (2026-05-28)**
**File:** `notifications_provider.dart` → `warehouseAlertNotificationItemsProvider`
**Problem:** `wh_low_stock`, `wh_missing_barcode`, `wh_missing_code` are always `isRead: false`
and `createdAt: DateTime.now()`. They cannot be marked as read. Badge stays inflated permanently.
**Fix:**
1. Add `final _warehouseAlertReadIdsProvider = StateProvider<Set<String>>((ref) => {});`
2. In `warehouseAlertNotificationItemsProvider`, set `isRead: readIds.contains(id)`.
3. In `_markAllRead` in `notifications_page.dart`, add `wh_` prefix handling.
4. Use `_todayStart` instead of `DateTime.now()` for stable sort order.
**Risk:** Low. Provider change only, no backend needed.

### TODO-04: Fix badge count mismatch (server count vs feed count) — **Done (2026-05-28)**
**File:** `notifications_page.dart`
**Problem:** `listEmptyButServerUnread` condition confuses separate count API with feed state.
**Fix:** Remove `appNotificationUnreadCountProvider` from page display logic.
Only use it for the "server load failed" banner. Badge uses `notificationsUnreadCountProvider` only.
**Risk:** Low.

---

## P1 — HIGH IMPACT UX FIXES (Do This Week)

### TODO-05: Add `const` constructors to home widgets
**Files:**
- `home_critical_alerts_grid.dart` → `const HomeCriticalAlertsGrid()`
- `home_warehouse_health_card.dart` → `const HomeWarehouseHealthCard()`
- `home_warehouse_activity_feed.dart` → `const HomeWarehouseActivityFeed()`
- `home_low_stock_section.dart` → `const HomeLowStockSection()`
- `home_staff_operations_panel.dart` → `const HomeStaffOperationsPanel()`
**Fix:** Add `const` keyword. Ensure no non-const parameters block this.
**Risk:** None. Compile-time check will catch issues.

### TODO-06: Fix `HomePurchaseControlCenter` — quantity first, money second
**File:** `home_purchase_control_center.dart`
**Problem:** `₹38,41,922` at `fontSize: 22, fontWeight: w900` is the dominant element.
Bags/KG/Boxes appear below in small chips.
**Fix:**
1. Show quantity row FIRST: `5,763 bags · 229,724 KG · 1 tin` at fontSize: 16–18, w900.
2. Move amount below: `₹38,41,922 · 37 bills` at fontSize: 14, w600, color: `textMuted`.
**Risk:** Low. Visual change only.

### TODO-07: Rebuild `HomeWarehouseHealthCard` to `HomeWarehouseSnapshotCard`
**File:** `home_warehouse_health_card.dart`
**Problem:** Shows `Stock value ₹34,24,334 · Items 572 · Bills 37`. No warehouse quantities.
`homeInventorySummaryProvider` already has `.bags`, `.kg`, `.boxes`, `.tins` — not used.
**Fix:**
1. Rename to `HomeWarehouseSnapshotCard`.
2. Primary row: `5,763 Bags · 229,724 KG · 12 Boxes · 1 Tin` (from `homeInventorySummaryProvider`).
3. Secondary row: `Low: 7 · Out: 567 · Mismatch: 2 · Pending: 19` (from existing providers).
4. Remove "Warehouse health" label + WARNING/GOOD/CRITICAL badge (confusing).
5. Remove `Stock value` as primary stat. Move to secondary/muted if needed.
**Risk:** Medium. Rename + logic change. Test with zero-value units (hide if 0).

### TODO-08: Move `HomeOwnerQuickActions` above `HomeWarehouseActivityFeed`
**File:** `home_page.dart`
**Problem:** Quick actions require 4+ scrolls.
**Fix:** In `home_page.dart` `Column`, swap order:
```
HomePurchaseControlCenter  (stays)
HomeWarehouseSnapshotCard  (rebuilt)
HomeOwnerQuickActions      ← MOVE HERE (was after activity feed)
HomeWarehouseActivityFeed  ← moves down
HomeStaffOperationsPanel   (stays)
HomeLowStockSection        (stays)
```
**Risk:** None. Order change only.

### TODO-09: Fix `HomeWarehouseActivityFeed` error state — compact retry
**File:** `home_warehouse_activity_feed.dart`
**Problem:** `FriendlyLoadError` renders ~300px tall card with icon + text + full Retry button.
**Fix:** Replace with:
```dart
error: (_, __) => ListTile(
  dense: true,
  leading: const Icon(Icons.warning_amber_rounded, size: 16),
  title: const Text('Activity unavailable', style: TextStyle(fontSize: 13)),
  trailing: TextButton(
    onPressed: () => ref.invalidate(homeRecentActivityFeedProvider),
    child: const Text('Retry'),
  ),
),
```
Height: ~44px instead of ~300px. Never blank, never giant.
**Risk:** None.

### TODO-10: Fix staff home — use `stockOnHandTotalsProvider` not owner provider
**File:** `staff_warehouse_totals_card.dart`
**Problem:** Card **display** already uses `stockOnHandTotalsProvider`. `_openSubcategorySheet` still calls `homeOwnerPeriodDashboardProvider` (owner financial breakdown).
**Fix:** Remove owner sheet; on unit tile tap navigate to `/staff/stock` (or staff-safe category filter). Do not call owner period dashboard from staff home.
**Risk:** Low.

### TODO-11: Fix activity feed — add all action types
**File:** `home_owner_dashboard_providers.dart` → `homeRecentActivityFeedProvider`, `home_warehouse_activity_feed.dart`
**Problem:** Feed is **not** purchase-only today — it merges `listTradePurchases` + `listStockAuditRecent` + `listStaffPurchaseLogs`. Missing rich labels/icons for adjustment types and delivered purchases.
**Fix:**
1. Map `StockAdjustmentOut.adjustment_type` to kinds: `physical_count`, `correction`, `opening`, `delivery`, etc.
2. Add purchase rows where `is_delivered` flipped true → kind `delivery_verified`.
3. Extend `_ActivityRow` icon switch for `delivery_verified`, `stock_correction`, `reorder`, `opening_stock_set`.
4. Optional backend: `GET /activity-log` business-wide + `action_types[]` (current API is per-user only).
**Risk:** Medium.

---

## P2 — PERFORMANCE FIXES (Do This Sprint)

### TODO-12: Staggered provider invalidation in home page
**File:** `home_page.dart` → `_invalidateHomeDataProviders()`
**Problem:** 10+ providers invalidated simultaneously every 30 seconds.
**Fix:** See `PERFORMANCE_AUDIT.md` Issue 1 for exact staggered implementation.
**Risk:** Low. Adds delays — verify alerts still appear quickly.

### TODO-13: Add `keepAlive` TTL to expensive home providers
**File:** `home_owner_dashboard_providers.dart`
**Target providers:** `homeInventorySummaryProvider`, `homeDashboardDataProvider`, `homeRecentActivityFeedProvider`
**Fix:** Add `keepAlive` with 3-minute TTL. See `PERFORMANCE_AUDIT.md` Issue 9.
**Risk:** Low. Data is slightly stale on tab return (max 3 min) — acceptable for warehouse.

### TODO-14: Add `keepAlive` to notifications provider — **Done (2026-05-28)**
**File:** `server_notifications_provider.dart`
**Fix:** Add 2-minute `keepAlive` to `appNotificationsListProvider`.
Prevents flash-of-empty when opening notifications page repeatedly.
**Risk:** Low.

### TODO-15: Fix `homeDashboardDataProvider` snapshot usage
**Files:** `home_warehouse_health_card.dart`, `home_purchase_control_center.dart`
**Problem:** `.snapshot.data` returns null during loading → visual pop from empty to data.
**Fix:** Use `.when(loading, error, data)` with proper skeleton loading in each widget.
**Risk:** Medium. UI change, needs skeleton designs.

---

## P3 — BUSINESS LOGIC IMPROVEMENTS (Next Sprint)

### TODO-16: Add physical stock warning on item detail
**File:** `item_detail_page.dart` or `item_stock_snapshot_card.dart`
**Problem:** Items with `system_stock > 0` but `physical_stock = 0` show no warning.
**Fix:** Show yellow warning banner when physical count was never performed.
**Risk:** Low. Display only.

### TODO-17: Fix item ledger default period
**Files:** `item_ledger_section.dart` (already `d30`), `trade_ledger_page.dart` (full statement)
**Problem:** Inline `ItemLedgerSection` already defaults to **30d**. Full statement `TradeLedgerPage` uses `_dateChip = 'All'` → 2020 start.
**Fix:** Default `TradeLedgerPage` to `This Month` (or add `30 Days` chip).
**Risk:** None.

### TODO-18: Remove "Notification settings" icon until real settings exist — **Done (2026-05-28)**
**File:** `notifications_page.dart` → AppBar `actions`
**Problem:** Settings icon opens a sheet that says "Not available yet". Broken UX.
**Fix:** Remove `IconButton(Icons.tune_rounded, ...)` from AppBar actions.
Add back when actual settings are implemented.
**Risk:** None.

### TODO-19: Role-based notification filtering — **Done (2026-05-28)**
**File:** `notifications_provider.dart` → `warehouseAlertNotificationItemsProvider`
**Problem:** All roles see all notifications including financial ones (staff shouldn't).
**Fix:** Add role check. See `NOTIFICATIONS_SYSTEM_AUDIT.md` Role Matrix table.
**Risk:** Medium. Test each role.

### TODO-20: Fix `Out (567)` — add active_out filter
**File:** Backend `GET /stock` endpoint + frontend `stockStatusCountsProvider`
**Problem:** 567 "out" items include legacy catalog items never purchased.
**Fix:** Add `active_out` filter — stock = 0 AND (opening_stock > 0 OR total_purchased > 0).
**Risk:** High. Backend schema change. Coordinate with backend.

---

## CURSOR IMPLEMENTATION ORDER

Run these in Cursor in exact sequence. Each TODO is independent unless noted.

```
Session 1: TODO-01, TODO-02, TODO-05      (Quick wins, 2 hours total)
Session 2: TODO-03, TODO-04               (Notification badge fix, 2 hours)
Session 3: TODO-06, TODO-07, TODO-08      (Home dashboard rebuild, 3 hours)
Session 4: TODO-09, TODO-10, TODO-11      (Activity + staff fixes, 2 hours)
Session 5: TODO-12, TODO-13, TODO-14, TODO-15  (Performance, 3 hours)
Session 6: TODO-16 through TODO-20        (Polish + business logic, 4 hours)
```

Total estimated: ~16 hours of focused Cursor sessions.
