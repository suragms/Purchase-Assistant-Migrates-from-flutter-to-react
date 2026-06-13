# Test Results — Production Recovery

**Date:** 2026-06-02

## Backend (pytest)

**Command:**
```bash
python -m pytest tests/test_trade_purchases.py tests/test_purchase_stock_increment.py tests/test_stock_workflow_rebuild.py -q --tb=short
```

**Result:** **36 passed** in ~15s  
**Warnings:** Pydantic `json_encoders` deprecation (pre-existing, 91 warnings)

### Coverage areas

- Trade purchase CRUD and permissions
- Staff delivery verify without financial edits
- Stock increment on commit workflow
- Stock workflow rebuild scenarios

## Flutter (analyze)

**Command:**
```bash
flutter analyze lib/features/purchase lib/features/barcode lib/core/providers/stock_providers.dart lib/core/auth/session_notifier.dart
```

**Result:** **0 errors**

| Severity | Count | Notes |
|----------|-------|-------|
| warning | 2 | Unused imports in `purchase_home_page.dart` (pre-existing) |
| info | 2 | `dart:html` deprecation in barcode web helper (pre-existing) |

## Barcode scan performance (2026-06-03)

| Check | Status |
|-------|--------|
| iOS 17+ Safari live camera (`preferUploadBarcodeOnWeb`) | Code |
| Scan debounce 200ms, 3 formats, detection timeout web 400ms / native 100ms | Code |
| iOS PWA fresh `MobileScannerController` on each scan page entry | Code (`e630e47`) |
| Lookup SnackBar + `_busy` finally | Code |
| Backend parallel lookup + 30s TTL cache | Code |
| Alembic **058** barcode indexes | Migration added |
| Native PDF `compute()`, print progress UI | Code |
| Bulk print >50 confirm + batches of 20 | Code |

**Commands (run after deploy):**
```bash
cd backend && python -m pytest tests/test_barcode_item_code.py tests/test_barcode_lookup_cache.py -q
cd flutter_app && flutter analyze lib/features/barcode
```

**Result (2026-06-03):** pytest barcode tests **3 passed**; `flutter analyze lib/features/barcode` **0 issues**.

## Stock + barcode fix (2026-06-13)

| Check | Result |
|-------|--------|
| `flutter analyze` (stock/barcode/invalidation paths) | No issues |
| `stock_list_row_patch_test.dart` | 7 passed (incl. `serverRowNewerThanPatch` reconcile) |
| `barcode_camera_session_test.dart` | 2 passed |
| Commit | `e630e47` on `main` |

**Device QA (pending):** G2 physical count immediate PHYS; G3 system stock immediate SYS; G4 iOS PWA multi-scan after back navigation.

## Manual QA matrix (recommended before release)

| Case | Platform | Expected |
|------|----------|----------|
| Quick-add item → purchase bag 30kg | Web + Android | Save succeeds |
| Barcode scan in warehouse | iOS + Android | Lookup < 8s |
| Staff verify → owner commit | Any | Stock increases after commit only |
| Staff home → Deliveries | Desktop | Route loads |

## CI alignment

Per `.cursorrules` Phase 7: PR should run full `flutter test`, `flutter analyze`, `pytest`.

## Flutter canonical cleanup (2026-06-03)

| Check | Status |
|-------|--------|
| `docs/cleanup/cleanup_report.md` + migration + checklist | Done |
| Router: `/reports` → `reports_shell_page.dart` | Done |
| Router: `/purchase/scan` → `ScanPurchaseV2Page` | Done |
| DEPRECATED headers on 5 orphan files (no deletes) | Done |
| `tool/find_dart_orphans.dart` | Added |

**Commands:**
```bash
cd flutter_app
flutter pub get
flutter analyze
flutter test
dart run tool/find_dart_orphans.dart
```

**Result (2026-06-03):** `flutter analyze` on router — **0 issues**; full project analyze has **2 pre-existing errors** in `purchase_accounts_share_web.dart` (web-only). **`flutter test` — 257 passed.**

## Sign-off

Automated targeted suites **PASS** for recovery scope. Device smoke remains operator responsibility (camera permissions, offline queue).
