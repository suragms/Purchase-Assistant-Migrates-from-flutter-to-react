# Deprecated Flutter Files

Do not use in new code. Removal scheduled only after zero-reference verification (see `verification_checklist.md`).

| File | Since | Replacement | Status |
|------|-------|-------------|--------|
| `lib/features/contacts/presentation/item_wizard_page.dart` | 2026-06-03 | `CatalogItemCreatePage` (`/catalog/item/create`) | **Removed 2026-06-06** |
| `lib/features/barcode/presentation/public_barcode_lookup_page.dart` | 2026-06-03 | `PublicItemScanPage` (`/item/:lookupKey` QR token) | **Removed 2026-06-06** |
| `backend/app/routers/public_barcode.py` | 2026-06-03 | `public_items.py` (QR/public token only) | **Removed 2026-06-06** |
| `admin_web/` (entire folder) | 2026-06-03 | Not deployed; local-only super-admin | **Removed 2026-06-06** |
| `lib/features/catalog/presentation/catalog_item_purchase_history_page.dart` | 2026-06-03 | `ItemHistoryPage`, item detail trade section | Low |
| `lib/core/providers/home_insights_provider.dart` | 2026-06-03 | None (unused) | **Removed from tree** |
| `lib/core/router/page_transitions_v2.dart` | 2026-06-03 | `page_transitions.dart` | **Removed from tree** |
| `lib/features/purchase/presentation/widgets/add_item_entry_page.dart` | 2026-06-03 | `PurchaseItemEntrySheet` | **Removed from tree** |

## Shims (keep; not deprecated)

| File | Purpose |
|------|---------|
| `lib/features/stock/presentation/barcode_scan_page.dart` | Re-export canonical barcode scan |
| `lib/features/purchase/presentation/scan_purchase_page.dart` | Route wrapper → v2 |
| `lib/features/dashboard/presentation/home_page.dart` | Re-export owner home |
| `lib/features/catalog/presentation/catalog_add_item_page.dart` | Preset taxonomy route wrapper |
| `lib/features/stock/presentation/update_stock_sheet.dart` | Public API → quick stock sheet |

## Ops scripts

Render one-off upgrade scripts live under `backend/scripts/ops/` (not part of Alembic).
