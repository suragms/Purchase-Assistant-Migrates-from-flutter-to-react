# SQL and migration index

**Canonical schema path (production):** Alembic `backend/alembic/versions/` — run `python -m alembic upgrade head` from `backend/`.

**This folder (`backend/sql/`):** Idempotent SQL mirrors and supplemental packs. Many numbered files are loaded by matching Alembic revisions; others are manual / Supabase-only.

See also: [migrations_and_backfill.md](../docs/migrations_and_backfill.md), [alembic/versions/README.md](../alembic/versions/README.md).

---

## A — Alembic chain (001 → 058, head)

Revisions **026** and **027** are absent in git (jump **025** → **028**). Do not renumber production revisions.

| Rev | ID | Summary |
|-----|-----|---------|
| 001 | `trade_purchase_core` | Bootstrap ORM schema (CI SQLite, fresh DB) |
| 002 | `line_kg` | `kg_per_unit`, `landing_cost_per_kg` on lines |
| 003 | `contact_email` | `businesses.contact_email` |
| 005 | `item_code_tpline` | `item_code` on `trade_purchase_lines` |
| 007 | `ssot_tp_fks` | Supplier/catalog FK backfill, NOT NULL |
| 008 | `tp_profit` | Landing/selling/profit subtotals on header |
| 009 | `strict_decimal_precision` | Decimal precision for purchase accounting |
| 010 | `tp_line_decimals` | Item-level decimal fields on lines |
| 011 | `tp_line_unit_type` | Canonical `unit_type` on lines |
| 012 | `trade_dashboard_indexes` | Dashboard/report date indexes |
| 013 | `trade_line_indexes` | Line lookup + partial indexes |
| 014 | `broker_deal_defaults` | Broker deal-default columns |
| 015 | `trade_purchase_commission_mode` | Commission mode on purchases |
| 016 | `catalog_item_last_trade_snapshot` | Last trade snapshot on catalog |
| 017 | `broker_image_url` | `brokers.image_url` |
| 018 | `purchase_scan_traces` | Scan trace audit table |
| 019 | `smart_unit_intelligence` | Master units, packaging, catalog columns |
| 020 | `home_reports_line_indexes` | Trade line report indexes |
| 021 | `trade_purchase_delivery` | Delivery tracking on purchases |
| 022 | `trade_purchase_list_status_date` | List filter composite index |
| 023 | `catalog_business_active_partial` | Active catalog partial index |
| 024 | `harisree_sql_parity` | User/stock/notifications parity SQL |
| 025 | `user_system_rebuild` | User system rebuild columns |
| 028 | `user_mgmt_v2` | `is_blocked`, admin role, activity types |
| 029 | `stockease_operations` | Perishable, daily usage, checklist |
| 030 | `catalog_barcode` | Packaging barcode column |
| 031 | `stock_audit_business` | Stock audits `business_id` |
| 032 | `staff_activity_action_types` | Extended `action_type` CHECK |
| 033 | `catalog_public_qr` | Catalog `public_token` (QR) |
| 034 | `stock_physical_counts` | Physical count entries |
| 035 | `opening_stock` | Opening stock setup fields |
| 036 | `staff_purchase_logs` | Staff cash purchase logs |
| 037 | `stock_movements` | Stock movement ledger |
| 038 | `notification_alert_v2` | Notification v2 columns |
| 039 | `stock_dispute_cases` | Stock dispute cases |
| 040 | `purchase_delivery_tracking` | `delivery_status` pipeline |
| 041 | `purchase_delivery_extras` | Dispatch note, delivered qty |
| 042 | `catalog_stock_list_sort_index` | `last_stock_updated_at` index |
| 043 | `audit_perf_indexes` | Audit/opening/FK indexes |
| 044 | `catalog_current_stock_non_negative` | `current_stock >= 0` CHECK |
| 045 | `purchase_delete_integrity` | Delete integrity + indexes |
| 046 | `report_saved_views` | Report saved views |
| 047 | `purchase_line_received_qty` | Line `received_qty` |
| 048 | `stock_commit_backfill_guards` | Commit backfill guards |
| 049 | `stock_ledger_sql_backfill` | Ledger backfill from adjustments |
| 050 | `stock_ledger_replay_current_stock` | Replay ledger → `current_stock` |
| 051 | `delivery_discrepancy_and_lifecycle` | Discrepancy + lifecycle events |
| 052 | `stock_movement_unit_mismatch_flag` | `unit_mismatch_flag` |
| 053 | `purchase_lifecycle_statuses` | Status lifecycle constraint |
| 054 | `enable_rls_business_policies` | RLS business policies |
| 055 | `business_whatsapp_contact` | `accounts_whatsapp_number` |
| 056 | `purchase_damage_reports` | Damage reports table |
| 057 | `purchase_damage_reports_v2` | Damage report workflow columns |
| 058 | `barcode_lookup_indexes` | Barcode lookup performance indexes (**head**) |

Inspect live chain: `cd backend && python -m alembic heads`

---

## B — `backend/sql/` files (by prefix)

### Numbered (deploy order hint)

| File | Alembic twin | Purpose |
|------|--------------|---------|
| `021_stock_inventory.sql` | Partial / legacy | Stock columns on `catalog_items` |
| `022_user_management.sql` | Partial | User management columns |
| `023_notifications.sql` | Partial | Notifications tables |
| `024_trade_line_tax_mode.sql` | — | Line `tax_mode` |
| `025_reorder_list.sql` | — | Reorder list |
| `026_stock_audits.sql` | — | Stock audits (pre-031 pack) |
| `027_user_system_rebuild.sql` | **025** revision loads this path | User rebuild |
| `028_user_mgmt_v2.sql` | **028** | User mgmt v2 |
| `029_stockease_operations.sql` | **029** | StockEase ops |
| `030_catalog_barcode.sql` | **030** | Barcode column |
| `031_stock_audit_business.sql` | **031** | Audit business scope |
| `032_staff_activity_action_types.sql` | **032** | Staff activity types |
| `033_catalog_public_qr.sql` | **033** | Public QR token |
| `033b_trade_line_qty_in_stock_unit.sql` | **Supplemental only** | `qty_in_stock_unit` on lines; use with `scripts/backfill_line_stock_unit_qty.py` |
| `034_stock_physical_counts.sql` | **034** | Physical counts |
| `034b_master_fix_v3_prod_parity.sql` | — | Prod parity pack (manual; was duplicate `034_` prefix) |
| `035_opening_stock.sql` | **035** | Opening stock |
| `035b_schema_parity_confirm.sql` | — | Schema parity confirm (manual; was duplicate `035_` prefix) |
| `036_staff_purchase_logs.sql` | **036** | Staff purchase logs |
| `037_stock_movements.sql` | **037** | Stock movements |
| `038_notification_alert_v2.sql` | **038** | Notifications v2 |
| `039_stock_dispute_cases.sql` | **039** | Dispute cases |
| `040_purchase_delivery_tracking.sql` | **040** | Delivery pipeline |
| `041_purchase_delivery_extras.sql` | **041** | Delivery extras |
| `042_catalog_stock_list_sort_index.sql` | **042** | Stock list sort index |
| `043_audit_perf_indexes.sql` | **043** | Audit perf indexes |
| `044_catalog_current_stock_non_negative.sql` | **044** | Non-negative stock CHECK |
| `045_purchase_delete_integrity.sql` | **045** | Delete integrity |
| `046_report_saved_views.sql` | **046** | Saved views |
| `047_purchase_line_received_qty.sql` | **047** | `received_qty` |
| `051_delivery_discrepancy_and_lifecycle.sql` | **051** | Discrepancy + lifecycle |
| `052_stock_movement_unit_mismatch_flag.sql` | **052** | Unit mismatch flag |
| `053_purchase_lifecycle_statuses.sql` | **053** | Lifecycle statuses |
| `054_enable_rls_business_policies.sql` | **054** | RLS policies |
| `055_business_whatsapp_contact.sql` | **055** | WhatsApp contact |
| `056_purchase_damage_reports.sql` | **056** | Damage reports |
| `057_purchase_damage_reports_v2.sql` | **057** | Damage reports v2 |
| `058_barcode_lookup_perf.sql` | **058** | Barcode / item_code lookup indexes |

**Note:** `033_catalog_public_qr` is the Alembic **033** revision. `033b_*` is a sibling supplemental script — do not rename to `033_` (avoids runner sort confusion).

### Unnumbered / optional

| File | Purpose |
|------|---------|
| `supabase_019_smart_unit_intelligence.sql` | Optional mirror of Alembic 019 for Supabase SQL editor |
| `supabase_020_ocr_learning.sql` | Optional OCR learning pack |
| `suggested_indexes_trade_reports.sql` | Suggested report indexes (not auto-run) |
| `index_trade_purchases_reporting.sql` | Reporting indexes |
| `optional_pg_trgm_indexes.sql` | Optional trigram indexes |
| `_019_min.sql`, `_019_compact.sql` | Compact 019 variants |

---

## C — Pairing rules

1. **Production:** Prefer `alembic upgrade head` only. Do not apply numbered SQL manually unless ops runbook says so.
2. **Alembic + SQL:** Revisions **029–057** (and **033**, **034**, etc.) often execute matching `backend/sql/NNN_*.sql` via `_SQL = Path(...)` in the revision module.
3. **Supplemental:** `033b_trade_line_qty_in_stock_unit.sql`, `034b_master_fix_v3_prod_parity.sql`, `035b_schema_parity_confirm.sql`, `supabase_*`, `suggested_*`, `optional_*` — document in runbooks; not all have Alembic twins.
4. **After manual SQL:** Set `alembic_version.version_num` to the revision you intend before the next `upgrade head`.

---

## Artifacts (not migrations)

One-off audit outputs: [backend/docs/migrations/artifacts/](../docs/migrations/artifacts/) (e.g. pre/post row counts).
