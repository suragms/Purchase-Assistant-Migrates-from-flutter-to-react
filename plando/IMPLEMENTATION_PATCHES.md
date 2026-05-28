# Implementation Patches — Sessions 1–6

Apply in **Agent mode** in session order. See [TODO_IMPLEMENTATION.md](TODO_IMPLEMENTATION.md).

## Session 1

### TODO-01 — `stock_alerts_summary`

`backend/app/schemas/stock.py` — add field:

```python
active_out_of_stock: int = 0
```

`backend/app/routers/stock.py` — `total_items` = full catalog count; compute `active_out` (out + opening or last_purchase).

`stock_providers.dart` — `'out': summary['active_out_of_stock'] ?? summary['out_of_stock']`.

### TODO-02 — `home_page.dart`

Delete `_OpeningStockSetupBanner` class and its widget usage.

### TODO-05 — const widgets

Already `const` at call sites; ensure widget constructors are `const` where possible.

## Session 2

### TODO-03 — `notifications_provider.dart`

Add `warehouseAlertReadIdsProvider`, `_warehouseAlertDayStart()`, wire `isRead` on `wh_*`.

### TODO-04 — `notifications_page.dart`

Remove `listEmptyButServerUnread` from list UI; error banner on `serverAsync.hasError` only.

## Session 3

### TODO-06 — `home_purchase_control_center.dart`

Units row first (16–18 w900); `homeInr` + bills below (14 muted).

### TODO-07 — Rename to `home_warehouse_snapshot_card.dart`

Rebuild per [HOME_DASHBOARD_REBUILD.md](HOME_DASHBOARD_REBUILD.md).

### TODO-08 — `home_page.dart` column order

Snapshot → Quick actions → Activity → Staff panel → Low stock.

## Session 4

### TODO-09 — compact activity error in `home_warehouse_activity_feed.dart`

### TODO-10 — `staff_warehouse_totals_card.dart` → `/staff/stock` on tap

### TODO-11 — audit adjustment_type + delivery rows in `home_owner_dashboard_providers.dart`

## Session 5

### TODO-12–15 — See [PERFORMANCE_AUDIT.md](PERFORMANCE_AUDIT.md)

## Session 6

### TODO-16–20 — See [TODO_IMPLEMENTATION.md](TODO_IMPLEMENTATION.md) P3 section
