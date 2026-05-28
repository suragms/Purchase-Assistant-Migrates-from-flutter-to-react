# Plando — Warehouse ERP implementation hub

**Canonical location** for the 2026-05-28 home / notifications / stock sprint.

Read in order:

1. [TODO_IMPLEMENTATION.md](TODO_IMPLEMENTATION.md) — P0→P3 checklist + session order
2. [PERFORMANCE_AUDIT.md](PERFORMANCE_AUDIT.md) — Issues 1–9 (stagger, keepAlive)
3. [NOTIFICATIONS_SYSTEM_AUDIT.md](NOTIFICATIONS_SYSTEM_AUDIT.md) — Badge, `wh_*`, role matrix
4. [HOME_DASHBOARD_REBUILD.md](HOME_DASHBOARD_REBUILD.md) — Owner layout spec
5. [STAFF_HOME_REBUILD.md](STAFF_HOME_REBUILD.md) — Staff dashboard spec
6. [STOCK_SYSTEM_AUDIT.md](STOCK_SYSTEM_AUDIT.md) — Stock flow, chip counts, Phase B
7. [UIUX_AUDIT.md](UIUX_AUDIT.md) — Density, errors, loading

Also see Harisree product rules: [docs/harisree/MASTER_REFERENCE.md](../docs/harisree/MASTER_REFERENCE.md)  
Living board: [TASKS.md](../TASKS.md)

## Code-verified corrections (2026-05-28)

| TODO | Plando text | Actual root cause |
|------|-------------|-------------------|
| **01** | `stockItems.length` on chip | Chips use `stockStatusCountsProvider` → `getStockAlertsSummary`. Backend set `total_items` to **active stock only** (`current_stock > 0`), not catalog total. Fix `backend/app/routers/stock.py` `stock_alerts_summary`. |
| **10** | Replace owner provider entirely | Display already uses `stockOnHandTotalsProvider`; only **subcategory sheet** still calls `homeOwnerPeriodDashboardProvider`. |
| **11** | Only `PURCHASE_CREATE` | Feed already merges purchases + audit + staff logs. Enrich audit `adjustment_type` mapping; optional activity-log API extension. |
| **17** | `item_ledger_section` defaults All | Section already defaults **30d**; fix **`TradeLedgerPage`** (`_dateChip = 'All'`). |

Delivery stock: `patch_trade_purchase_delivery` already calls `apply_confirmed_purchase_stock` only on confirm — see Phase 2 in `docs/harisree/IMPLEMENTATION_PHASES.md`.
