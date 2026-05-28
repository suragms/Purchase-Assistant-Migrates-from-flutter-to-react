# HOME DASHBOARD REBUILD — OWNER/ADMIN
## Harisree Warehouse ERP · Deep Audit + Rebuild Spec

### Implemented 2026-05-28

Owner home matches the **Final widget render order** below. Key code paths:

| Spec item | File |
|-----------|------|
| Column order (snapshot → purchase → quick actions → activity → low stock) | `flutter_app/lib/features/home/presentation/home_page.dart` |
| Warehouse snapshot (qty-first, no health badge) | `home_warehouse_snapshot_card.dart` (replaces deleted `home_warehouse_health_card.dart`) |
| Purchase center (qty-first, muted amount) | `home_purchase_control_center.dart` |
| Critical alerts priority + 4-card cap | `home_critical_alerts_grid.dart` (pending → low → opening → mismatch → export/sync) |
| Quick actions 2×4 incl. Reorder | `home_owner_quick_actions.dart` → `/stock/reorder-suggestions` |
| Polling tiers | `home_page.dart`: 30s alert providers; 60s full stagger invalidation |
| Section spacing | `HexaOp.cardGap` (12) between main column sections |
| Staff operations panel | Removed from home column; pending delivery surfaced via alerts + notifications |
| Opening stock banner | Removed from `home_page.dart` (deduped with alerts grid) |

---

> Based on: actual code audit of `home_page.dart`, `home_warehouse_snapshot_card.dart`,
> `home_purchase_control_center.dart`, `home_warehouse_activity_feed.dart`,
> `home_owner_dashboard_providers.dart`, screenshots, and all widget files.

---

## CONFIRMED PROBLEMS FROM CODE

### 1. Wrong Information Hierarchy
**Code evidence — `home_page.dart` widget order:**
```
HomePurchaseControlCenter   ← PURCHASE MONEY FIRST
HomeWarehouseHealthCard     ← Stock value (₹34,24,334) dominates
HomeWarehouseActivityFeed   ← Too far down
HomeStaffOperationsPanel    ← Buried
HomeOwnerQuickActions       ← Extremely far below fold
HomeLowStockSection         ← Last item, never seen
```
**Problem:** Owner sees ₹34,24,334 stock value before seeing 567 Out-of-stock items.
This is backwards for a warehouse operations dashboard.

### 2. Warehouse Activity Feed — "Could Not Load Activity" Giant Error
**Screenshot evidence:** A huge 300px+ empty card with cloud icon, message, and full-width Retry button.
**Code:** `FriendlyLoadError` inside `OperationalSection` — no skeleton, no cached fallback, no inline retry.
All activity goes blank on any API failure.

### 3. `HomePurchaseControlCenter` — Money is the Hero
**Code — `home_purchase_control_center.dart` line 66:**
```dart
Text(homeInr(dash.totalPurchase),
    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
```
₹ amount is the first and largest element at 22px bold. Bags/KG/Boxes/Tins appear below in smaller chips.
**Fix:** Flip order. Quantities first, amount secondary/muted.

### 4. `HomeWarehouseHealthCard` — Wrong Priority Order
**Code:** Shows `Stock value`, `Items`, `Bills` as the 3 stat columns.
`Stock value` is financial. The owner's first need is warehouse quantity — Bags, KG, Boxes, Tins.
The `homeInventorySummaryProvider` already has `bags`, `kg`, `boxes`, `tins` — they are just NOT shown in the health card.

### 5. Opening Stock Banner — Duplicate Alert
**Code:** `_OpeningStockSetupBanner` in `home_page.dart` fires from `openingStockMissingProvider`.
`HomeCriticalAlertsGrid` also shows opening stock alerts from `warehouseAlertsProvider`.
Two different widgets, same data source → duplicate opening stock warnings on dashboard.

### 6. Timer Architecture — 30-Second Polling Invalidates EVERYTHING
**Code — `_setHomePollingActive`:**
```dart
_rtPoll = Timer.periodic(const Duration(seconds: 30), (_) {
  _invalidateHomeDataProviders();  // invalidates 10 providers at once
});
```
Every 30 seconds: ALL 10 providers rebuild simultaneously.
`homeDashboardDataProvider`, `homeInventorySummaryProvider`, `stockAlertCountsProvider`,
`stockLowTopHomeProvider`, `stockAuditPeriodProvider`, `stockVariancesTodayProvider`,
`homeRecentActivityFeedProvider`, `warehouseAlertsProvider`, `appNotificationUnreadCountProvider`,
`lowStockByCategoryProvider`, `stockStatusCountsProvider` — all fire at the same time.
**Result:** UI freezes for 1–2 seconds every 30 seconds on low-end devices.

### 7. Warehouse Activity Feed — Only Shows "Purchase added"
**Screenshot evidence:** All 15 rows in activity feed show only `Purchase added` with supplier + amount.
No stock updates, no delivery verifications, no corrections.
**Root cause:** `homeRecentActivityFeedProvider` fetches `listActivityLog` which is filtered
to only `PURCHASE_CREATE` action types in practice, not the full warehouse activity.

### 8. Quick Actions Too Far Down — Never Reached
**Code:** `HomeOwnerQuickActions` is rendered AFTER `HomePurchaseControlCenter`, `HomeWarehouseHealthCard`,
`HomeWarehouseActivityFeed`, `HomeStaffOperationsPanel`. That's 4 large cards before actions.
On mobile, Quick Actions require 4+ full scrolls.

### 9. `stockStatusCountsProvider` shows `All(5)` but `Out(567)` in Stock
**Screenshot:** Stock page shows `All (5)` with filter active but `Out (567)` items exist.
This is a filter display bug — the `All` count only shows the current page's visible items (5),
not total items. The count label logic in stock page is wrong.

---

## NEW DASHBOARD STRUCTURE — PRIORITY ORDER

### SECTION 1 — Top Operation Bar (KEEP, COMPACT)
Current `HomeCompactHeader` is acceptable. Keep.
- LEFT: workspace name, sync dot
- RIGHT: notification bell with badge, settings icon

**Fix:** Remove `HomeSessionDataBanner` — it adds ~60px of empty space when there's no session message.

---

### SECTION 2 — LIVE Status Strip (ALREADY EXISTS, FIX IT)
`HomeLiveStatusBar` is correct but hidden behind `HomeSessionDataBanner`.

**Contents (already in provider data):**
```
● LIVE · Synced · 19 pending · 7 low stock · 2 mismatch
```
Move to immediately after header. Make it always visible.

---

### SECTION 3 — Critical Alerts Grid (KEEP, DE-DUPLICATE)
`HomeCriticalAlertsGrid` exists but fires alerts that also appear in `_OpeningStockSetupBanner`.

**Fix:**
1. Delete `_OpeningStockSetupBanner` from `home_page.dart` entirely.
2. `HomeCriticalAlertsGrid` is the single source of all critical alerts.
3. Maximum 2 rows (4 cards). Priority: pending deliveries → low stock → opening stock → mismatch.

---

### SECTION 4 — WAREHOUSE SNAPSHOT (HIGHEST PRIORITY — REBUILD)

**Current:** `HomeWarehouseHealthCard` shows `Stock value ₹34,24,334 · Items 572 · Bills 37`.
Money-first. No quantities visible.

**Rebuild to show:**
```
CURRENT STOCK (from homeInventorySummaryProvider — already has this data)
  5,763 Bags   |   229,724 KG   |   12 Boxes   |   1 Tin

WAREHOUSE STATUS
  Low: 7  ·  Out: 567  ·  Mismatch: 2  ·  Pending Delivery: 19
```

**Data already available — no new API needed:**
- `homeInventorySummaryProvider` → `.bags`, `.kg`, `.boxes`, `.tins`
- `stockAlertCountsProvider` → `.low`, `.critical`
- `stockStatusCountsProvider` → `out`, `mismatch`
- `warehouseAlertsProvider` → `pendingDeliveries`

**Remove:** "Warehouse health" label + WARNING/GOOD/CRITICAL badge — confusing.
**Replace with:** Compact quantity grid + inline status chips.

**Widget:** Rename to `HomeWarehouseSnapshotCard`.

---

### SECTION 5 — PURCHASE OPERATIONS CENTER (REBUILD)

**Current `HomePurchaseControlCenter`:**
- ₹ amount at 22px bold = WRONG PRIORITY
- Bags/KG/Boxes/Tins shown as small chips below = WRONG

**Rebuild:**
```
Purchase Center (Month)
5,763 bags · 229,724 KG · 1 tin
─────────────────────────────────
₹ 38,41,922  ·  37 bills
19 pending · 14 received · 8 suppliers · 2 brokers
```

**Typography change:**
- Quantities: `fontWeight: w900, fontSize: 18`
- Amount: `fontWeight: w600, fontSize: 14, color: textMuted`

---

### SECTION 6 — WAREHOUSE ACTIVITY (MOVE UP + FIX)

**Current position:** After `HomeWarehouseHealthCard` and before Quick Actions.
**Problem:** Activity only shows "Purchase added". Need to show all action types.

**Fix `homeRecentActivityFeedProvider`:**
The provider must request `action_types=PURCHASE_CREATE,STOCK_UPDATE,DELIVERY_VERIFIED,STOCK_CORRECTION,REORDER_CREATED,BARCODE_PRINTED`.

**Fix error state:**
Replace giant `FriendlyLoadError` card with compact inline:
```
⚠ Activity unavailable  [Retry]
```
Max 24px height. Never a full-width 300px error card.

**Each row must show:**
- Action icon (purchase/stock/delivery/correction)
- Supplier or item name
- Qty + unit
- Time (relative)

---

### SECTION 7 — QUICK ACTIONS (MOVE UP)

**Current:** Buried after 4 large cards. Requires 4 scrolls.
**Fix:** Move to SECTION 3 position if no critical alerts, or immediately after Warehouse Snapshot.

**Grid — 2 rows × 4 columns:**
```
[Purchase] [Stock]  [Deliveries] [Low Stock]
[Reports]  [Users]  [Barcode]    [Reorder]
```

Use existing `HomeOwnerQuickActions` widget. Remove excessive padding.
Reduce card height from current ~80px to 56px.

---

### SECTION 8 — LOW STOCK CENTER (KEEP, COMPACT)

`HomeLowStockSection` is correct but buried. Move to visible position.
Already shows item, qty, reorder level. No rebuild needed beyond position.

---

## PERFORMANCE FIXES

### Fix 1 — Staggered Provider Invalidation
Replace simultaneous 10-provider invalidation with staggered approach:
```dart
// BAD (current)
void _invalidateHomeDataProviders() {
  ref.invalidate(homeDashboardDataProvider);
  ref.invalidate(homeInventorySummaryProvider);
  // ... 8 more
}

// GOOD
void _invalidateHomeDataProviders() {
  // Critical path first
  ref.invalidate(stockAlertCountsProvider);
  ref.invalidate(warehouseAlertsProvider);
  // Non-critical deferred by 200ms
  Future.delayed(const Duration(milliseconds: 200), () {
    if (!mounted) return;
    ref.invalidate(homeDashboardDataProvider);
    ref.invalidate(homeInventorySummaryProvider);
  });
  // Analytics deferred by 500ms
  Future.delayed(const Duration(milliseconds: 500), () {
    if (!mounted) return;
    ref.invalidate(homeRecentActivityFeedProvider);
    ref.invalidate(stockVariancesTodayProvider);
  });
}
```

### Fix 2 — Polling Interval
Change 30-second polling to 60-second for non-critical providers.
Keep 30s only for `stockAlertCountsProvider` and `warehouseAlertsProvider`.

### Fix 3 — Activity Feed Error State
Replace `FriendlyLoadError` (300px) with `_CompactRetry` (24px inline).

### Fix 4 — Missing `const` constructors
`HomeCriticalAlertsGrid`, `HomeWarehouseHealthCard`, `HomeWarehouseActivityFeed` —
none use `const` constructors. All must be `const ConsumerWidget` where possible
to prevent unnecessary rebuilds.

### Fix 5 — `shellCurrentBranchProvider` Guard
Current code already has branch guard:
```dart
if (ref.watch(shellCurrentBranchProvider) != ShellBranch.home) {
  return const SizedBox.shrink();
}
```
Good. Keep. Ensure ALL heavy providers inside widgets also check this guard.

---

## DESIGN SYSTEM — DO NOT BREAK EXISTING TOKENS

Existing tokens to use — **do not invent new ones**:

| Token | Value | Use |
|-------|-------|-----|
| `HexaColors.brandPrimary` | `#0E4F46` | Primary buttons, active states |
| `HexaColors.brandAccent` | `#159A8A` | Teal accents, chips |
| `HexaColors.brandGold` | `#D4AF37` | Profit, gold highlights |
| `HexaColors.profit` | `#16A34A` | Positive stock, healthy |
| `HexaColors.loss` | `#E53935` | Critical, out of stock |
| `HexaColors.warning` | `#F0A500` | Warning states |
| `HexaColors.brandBackground` | `#F7F9F6` | Page background |
| `HexaOp.cardPadding` | `14` | Card internal padding |
| `HexaOp.sectionGap` | `16` | Between sections |
| `HexaOp.listRowMin` | `64` | Minimum row height |
| `HexaDsType.heading(16)` | Plus Jakarta Sans 16 w800 | Card titles |
| `HexaDsType.body(13)` | Plus Jakarta Sans 13 | Subtitles, muted |

---

## SCROLL DEPTH TARGET

Current: ~6–7 screens to see Quick Actions.
Target: Quick Actions visible within 1.5 screens.

Remove these spacing items:
- `HomeSessionDataBanner` when empty: saves ~60px
- `_OpeningStockSetupBanner`: deduplicated, saves ~72px
- `SizedBox(height: 8)` between every section → use `HexaOp.cardGap` (12) only

---

## FINAL WIDGET RENDER ORDER

```dart
Column(children: [
  HomeCompactHeader(),                // ~56px
  HomeLiveStatusBar(),                // ~32px compact strip
  ResumePurchaseDraftBanner(),        // conditional ~56px
  HomeCriticalAlertsGrid(),           // max 2 rows ~120px
  HomeStickyPeriodHeader(),           // sticky 44px
  HomeWarehouseSnapshotCard(),        // ~96px (NEW - was WarehouseHealthCard)
  SizedBox(height: HexaOp.cardGap),
  HomePurchaseControlCenter(),        // ~100px (rebuilt, qty-first)
  SizedBox(height: HexaOp.cardGap),
  HomeOwnerQuickActions(),            // ~120px 2×4 grid (MOVED UP)
  SizedBox(height: HexaOp.cardGap),
  HomeWarehouseActivityFeed(),        // ~200px (moved down from above)
  SizedBox(height: HexaOp.cardGap),
  HomeLowStockSection(),              // ~120px
])
```

Total above-fold on 720px screen: Header + Strip + Alerts + Snapshot + Purchase = ~404px.
Quick Actions visible within first scroll. Target achieved.
