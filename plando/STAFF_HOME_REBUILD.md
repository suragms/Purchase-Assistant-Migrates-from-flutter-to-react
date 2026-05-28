# STAFF HOME DASHBOARD REBUILD
## Harisree Warehouse ERP · Staff Dashboard Deep Audit

### Implemented 2026-05-28

Staff home matches the **target section order** below. Key code paths:

| Spec item | File |
|-----------|------|
| Compact header (~52px) | `flutter_app/lib/features/staff/presentation/staff_home_page.dart` |
| Shift snapshot strip + shimmer | `staff_home_dashboard_widgets.dart` → `StaffHomeShiftSnapshotStrip` |
| Needs attention (pending → low → opening → barcodes → mismatch) | `staff_home_page.dart` + `staff_home_providers.dart` |
| Section order: snapshot → attention → start here → warehouse → recent → tools | `staff_home_page.dart` |
| `stockOnHandTotalsProvider` on warehouse card | `staff_warehouse_totals_card.dart` |
| Warehouse difference (this month) | `staff_warehouse_difference_card.dart` |
| Recent activity (merged log + scans) | `staffRecentActivityProvider`, `StaffHomeRecentActivitySection` |
| Compact tools grid | `StaffHomeToolsGrid` |
| Staff home focus (all / barcode / stock / purchase) | `staffHomeFocusProvider` + profile sheet picker |
| Removed duplicate low-stock list + “Stock received today” block | `staff_home_page.dart` |

---

> Based on: actual `staff_home_page.dart`, `staff_warehouse_totals_card.dart`,
> `staff_home_dashboard_widgets.dart`, `staff_home_providers.dart`, all screenshots.

---

## CONFIRMED PROBLEMS FROM CODE

### 1. Giant Header Greeting — Wastes Valuable Top Space
**Code — `staff_home_page.dart`:**
```dart
Text('Hello, $name', style: HexaDsType.heading(20, ...)),
SizedBox(height: 4),
// STAFF badge + date row
```
A 20px heading greeting + role badge + date takes ~72px at the very top.
Staff don't need "Hello, Suresh" — they need immediate task visibility.

### 2. `StaffWarehouseTotalsCard` — Opens a Bottom Sheet Instead of Showing Data
**Code — `staff_warehouse_totals_card.dart`:**
`_openSubcategorySheet()` is triggered. The card itself shows inline totals,
but tapping opens a subcategory modal. Staff don't need subcategory breakdown —
they need bags/kg/boxes/tins AT A GLANCE.
The card calls `homeOwnerPeriodDashboardProvider` (owner-level data) instead of
`stockOnHandTotalsProvider` (simpler, faster, staff-optimized).

### 3. "Recent Scans" — Horizontal Chip Scroll Hidden at Bottom
**Code:** `recentAsync` scans rendered as `ListView(scrollDirection: Axis.horizontal)` at 44px height.
This is **below**: Today summary → Needs attention → Warehouse on hand → Start here → Tools → Low stock alerts.
Recent scans (most important for barcode staff) appear last, requiring 6+ scrolls.

### 4. "Low Stock Alerts" at Bottom — Wrong Priority
**Code:** `lowAsync` data rendered at the very bottom of the page.
Low stock is a critical action item. It should be in "Needs attention" section, not its own section at bottom.

### 5. `StaffHomeTodaySummaryCard` — Loaded with `activityAsync`
```dart
activityAsync.when(
  loading: () => const SizedBox(height: 88, child: ListSkeleton(...)),
```
88px blank skeleton on every page load. Slow API = 88px blank for entire load duration.
Staff see an empty top of dashboard until this API call completes.

### 6. "Stock received today" — Wrong Section, Wrong Position
**Code:**
```dart
if (todayPurchases.isNotEmpty) ...[
  const StaffHomeSectionHeader(title: 'Stock received today'),
  ...todayPurchases.take(4).map((p) { ... Card(...) }),
]
```
This appears **after** Recent scans. It should be part of "Needs attention" if deliveries are unverified.

### 7. `StaffHomeActionGroup` Tools Section — Too Verbose
6 action rows: Search items, Update stock, Add new item, Bulk print labels, Purchase history, Low stock list.
Each row has title + subtitle → 72px per row × 6 = 432px just for tools.
Staff need a compact icon grid, not a menu list.

### 8. `staffLowStockAlertsProvider` — Duplicated in Two Places
Low stock shown in:
1. "Needs attention" tile: `StaffHomeAttentionTile` (count badge)
2. Bottom section: Full list with update action
Same data, two widgets, two provider reads. Only one needed.

### 9. Missing: Opening Stock Card
**Code search:** No opening stock widget in `staff_home_page.dart`.
The `openingStockMissingProvider` is only on the owner home page.
Staff need to see pending opening stock items — currently invisible.

### 10. Missing: Warehouse Difference Card
**Code search:** No purchased vs current difference card anywhere in staff home.
Staff can't see: "We bought 5200 bags, currently 4700 bags — 500 moved/sold."

---

## NEW STAFF HOME STRUCTURE

### SECTION 1 — Compact Staff Header
**Replace:**
```dart
// BAD — current 72px greeting
Text('Hello, $name', style: HexaDsType.heading(20))
```
**With:**
```dart
// GOOD — 52px operational header
Row(children: [
  CircleAvatar(initials, radius: 16),  // small avatar
  SizedBox(width: 8),
  Text(name, style: HexaDsType.heading(14)),  // smaller name
  Text(' · STAFF · ', style: body(12, muted)),
  Spacer(),
  Badge(bellCount, child: Icon(notifications_outlined)),
])
```

---

### SECTION 2 — Shift Snapshot Strip (REBUILD `StaffHomeTodaySummaryCard`)
**Current:** Full card loading skeleton (88px blank on load).
**Rebuild:** 4 compact metric tiles in a horizontal row, each showing a count.

```
[📦 Scans: 12] [✓ Stock: 4] [🛒 Purchases: 3] [🚚 Deliveries: 1]
```

**Critical fix:** Show skeleton tiles (shimmer) immediately, not blank space.
```dart
// Use const skeleton tiles while loading
Row(children: [
  _ShiftTile(label: 'Scans', value: activityAsync.maybeWhen(
    data: (s) => '${s.scansToday}',
    orElse: () => '–',  // show dash, not blank
  )),
  ...
])
```

---

### SECTION 3 — Needs Attention (EXPAND)
**Current:** Shows pending deliveries, missing barcodes, low stock.
**Add:**
- Opening stock pending (from `openingStockMissingProvider`)
- Stock mismatch alert (from `stockStatusCountsProvider['mismatch']`)

**Order by urgency:**
1. Pending deliveries (orange)
2. Low stock (red)
3. Opening stock (amber)
4. Missing barcodes (blue)
5. Stock mismatch (red)

---

### SECTION 4 — Start Here (KEEP, REDUCE HEIGHT)
**Current:** Scan button (52px) + 2 secondary buttons (44px each).
Good structure. Just reduce spacing:
- Remove `SizedBox(height: 12)` between scan and secondary row
- Use `SizedBox(height: 8)` = saves 4px × 2 = minor but matters

**Scan button:** Keep large (52px), primary CTA. Perfect.

---

### SECTION 5 — Warehouse On Hand (FIX DATA SOURCE)
**Current problem:** `StaffWarehouseTotalsCard` uses `homeOwnerPeriodDashboardProvider`.
This is an OWNER provider. Staff home should use `stockOnHandTotalsProvider` (direct, fast).

**Fix:** Change provider in `StaffWarehouseTotalsCard`:
```dart
// BAD
final dash = ref.watch(homeOwnerPeriodDashboardProvider);

// GOOD
final totals = ref.watch(stockOnHandTotalsProvider);
```

**Warehouse Difference Card (ADD THIS):**
Show purchased vs current:
```
Purchased this month    Current on hand     Difference
5,200 bags             4,700 bags          -500 bags
```
Data: `homeDashboardDataProvider.totalBags` vs `homeInventorySummaryProvider.bags`.
Both providers already exist. Just display the diff.

---

### SECTION 6 — Tools (COMPACT GRID)
**Replace 432px verbose list with 96px icon grid:**
```
[🔍 Search] [📦 Stock]  [🖨 Labels] [📜 History]
[⚠ Low Stock] [💰 Cash Buy]
```

Use `StaffHomeActionGroup` pattern but as 3-column grid, not list rows.
Each tile: icon (28px) + label (11px) = 56px total tile height.
**Saves: ~376px (from 432px to ~56px)**

---

### SECTION 7 — Recent Activity (MOVE UP, ADD MORE TYPES)
Current: `recentAsync` only shows recent SCANS.
**Fix:** Show all recent staff activity (scans + stock updates + purchases).
**Move up:** Above Tools section. Staff need to see what they did recently.

---

## PERFORMANCE FIXES

### Fix 1 — Provider Separation
Staff home uses `homeOwnerPeriodDashboardProvider` in `StaffWarehouseTotalsCard`.
This provider makes a complex owner-level analytics API call that staff don't need.

**Replace with:** `stockOnHandTotalsProvider` which is already available in `stock_providers.dart`.

### Fix 2 — Skeleton Instead of Blank
Add `shimmer` loading to `StaffHomeTodaySummaryCard`:
```dart
activityAsync.when(
  loading: () => const _ShiftSnapshotSkeleton(),  // 4 shimmer tiles
  // ...
)
```

### Fix 3 — Remove Duplicate Low Stock Provider
`staffLowStockAlertsProvider` is read twice:
1. `lowCount` for attention tile badge
2. Full `lowAsync.data` for bottom list

Merge into one section. Remove the bottom section entirely.
"Needs attention" tile with tap → staff low stock page is sufficient.

### Fix 4 — `const` Constructors
`StaffHomePage` is a `ConsumerWidget` not `ConsumerStatefulWidget`.
All inner widgets like `StaffHomeSectionHeader`, `StaffHomeActionGroup` should be `const`.

---

## DESIGN SYSTEM — STAFF SPECIFIC TOKENS

Use existing tokens — same palette as owner, same `HexaOp` spacing:

| Element | Token | Notes |
|---------|-------|-------|
| Scan button | `HexaColors.brandPrimary` gradient | Keep as-is |
| Cash buy button | `Color(0xFF3B6D11)` green | Keep as-is |
| Low stock accent | `HexaColors.loss` `#E53935` | Keep |
| Pending delivery | `Color(0xFFBA7517)` amber | Keep |
| Missing barcode | `HexaColors.brandPrimary` blue-teal | Keep |
| Section headers | `HexaDsType.heading(13)` + `body(12, muted)` | Keep |

---

## SCROLL DEPTH TARGET

Current: 8+ screens to see all content.
Target: Core tasks within 1 screen.

**Above fold (720px screen):**
- Header: 52px
- Shift snapshot: 72px  
- Needs attention (3 items): 180px
- Scan button + secondary: 108px
= 412px total. Everything important above fold.

**Below fold (acceptable):**
- Warehouse on hand
- Tools grid
- Recent activity

---

## ROLE-BASED ADJUSTMENTS

### Barcode Staff (role hint from session)
Lead with: Scan barcode → Missing labels → Recent scans
Hide: Purchase entry, delivery sections

### Stock Staff
Lead with: Warehouse on hand → Low stock → Stock updates
Hide: Purchase history section

### Purchase Staff
Lead with: Pending deliveries → Cash buy → Purchase history
Hide: Barcode tools

**Implementation:** Check `session.primaryBusiness.role` or add a `staffSubRole` field.
Currently all staff see all sections. Conditional rendering via role check is a 1-day addition.
