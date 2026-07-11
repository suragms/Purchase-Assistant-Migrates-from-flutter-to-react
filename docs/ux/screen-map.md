# Screen Map — Purchase Assistant

> **Source of truth:** React (Vite + TypeScript + Tailwind) routes derived from Flutter GoRouter.
> All routes are mirrored; see `Status` column for implementation completeness.

---

## Legend

| Status | Meaning |
|--------|---------|
| ✅ Implemented | Fully functional component matching Flutter |
| 🟡 Stub | Route scaffolded, shows placeholder text |
| 🔄 Redirect | Route redirects to canonical target |
| ❌ Missing | Route not defined in React router |

---

## 1. Public Routes (No Auth)

| # | Path | Flutter Widget | React Component | Status |
|---|------|---------------|-----------------|--------|
| 1 | `/` | redirect → `/splash` | `<Navigate to="/splash">` | ✅ |
| 2 | `/splash` | `SplashPage` | `SplashPage` (127 lines) | ✅ |
| 3 | `/get-started` | redirect → `/login` | `<Navigate to="/login">` | ✅ |
| 4 | `/login` | `LoginPage` | `LoginPage` (359 lines) | ✅ |
| 5 | `/forgot-password` | `ForgotPasswordPage` | `ForgotPasswordPage` (150 lines) | ✅ |
| 6 | `/reset-password` | `ResetPasswordPage` | `ResetPasswordPage` (231 lines) | ✅ |
| 7 | `/scan/:token` | redirect → `/item/:token` | `<Navigate to="/item/:token">` | ✅ |
| 8 | `/item/:lookupKey` | `PublicItemScanPage` | `PublicItemScanPage` | 🟡 |

---

## 2. Owner Shell Routes (Bottom Nav / NavigationRail)

Shell: `ShellScreen` (Flutter) / `OwnerAppShell` (React). 5 tabs:

| Branch | Tab | Path | Flutter Widget | React Component | Status |
|--------|-----|------|---------------|-----------------|--------|
| 0 | Home | `/home` | `HomePage` | `HomePage` | 🟡 |
| 0 | — | `/home/activity` | `HomeWarehouseActivityPage` | `ActivityPage` | 🟡 |
| 0 | — | `/home/breakdown-more` | `HomeBreakdownListPage` | `BreakdownListPage` | 🟡 |
| 1 | Stock | `/stock` | `StockPage` (owner) | `StockPage` | 🟡 |
| 2 | Reports | `/reports` | `FullReportsPage` | `ReportsPage` | 🟡 |
| 3 | History/Purchase | `/purchase` | `PurchaseHomePage` | `PurchaseHomePage` | 🟡 |
| 4 | Search | `/search` | `SearchPage` | `SearchPage` | 🟡 |

---

## 3. Staff Shell Routes

Shell: `StaffShellScreen` (Flutter) / `StaffAppShell` (React). 6 tabs:

| Branch | Tab | Path | Flutter Widget | React Component | Status |
|--------|-----|------|---------------|-----------------|--------|
| 0 | Home | `/staff/home` | `StaffHomePage` | `StaffHomePage` | 🟡 |
| 1 | Stock | `/staff/stock` | `StockPage` (staff) | `StaffStockPage` | 🟡 |
| 1 | — | `/staff/stock/changes` | redirect → `?tab=changes` | ❌ **MISSING** | ❌ |
| 2 | Scan | `/staff/scan` | `BarcodeScanPage` | `StaffScanPage` | 🟡 |
| 3 | Search | `/staff/search` | `SearchPage` (embedded) | `StaffSearchPage` | 🟡 |
| 4 | Deliveries | `/staff/deliveries` | `StaffPendingDeliveriesPage` | `StaffDeliveriesPage` | 🟡 |
| 5 | Tasks | `/staff/tasks` | `StaffChecklistPage` | `StaffTasksPage` | 🟡 |

---

## 4. Contacts

| # | Path | Flutter Widget | React Component | Status |
|---|------|---------------|-----------------|--------|
| 23 | `/contacts` | `ContactsPage` | `ContactsPage` | 🟡 |
| 24 | `/contacts/supplier/new` | `SupplierCreateSimple` | `SupplierCreateSimplePage` | 🟡 |
| 25 | `/contacts/category` | `CategoryItemsPage` | `CategoryItemsPage` | 🟡 |

---

## 5. Catalog (18 routes)

| # | Path | Flutter Widget | React Component | Status |
|---|------|---------------|-----------------|--------|
| 26 | `/catalog` | `CatalogPage` | `CatalogPage` | 🟡 |
| 27 | `/catalog/missing-codes` | `CatalogMissingCodesPage` | `MissingCodesPage` | 🟡 |
| 28 | `/catalog/quick-add` | `CatalogItemCreatePage` | `QuickAddPage` | 🟡 |
| 29 | `/catalog/quick-add-from-scan` | `BarcodeQuickCreatePage` | `QuickAddFromScanPage` | 🟡 |
| 30 | `/catalog/setup-reorder-levels` | `CatalogSetupReorderLevelsPage` | `SetupReorderLevelsPage` | 🟡 |
| 31 | `/catalog/taxonomy` | `CatalogTaxonomyHubPage` | `TaxonomyHubPage` | 🟡 |
| 32 | `/catalog/new-category` | `CatalogAddCategoryPage` | `AddCategoryPage` | 🟡 |
| 33 | `/catalog/category/:categoryId/new-subcategory` | `CatalogAddSubcategoryPage` | `AddSubcategoryPage` | 🟡 |
| 34 | `/catalog/category/:categoryId/type/:typeId/add-item` | `CatalogAddItemPage` | `AddItemPage` | 🟡 |
| 35 | `/catalog/item/:itemId` | `ItemDetailPage` | `ItemDetailPage` | 🟡 |
| 36 | `/catalog/item/:itemId/edit` | `ItemEditPage` | `ItemEditPage` | 🟡 |
| 37 | `/catalog/item/:itemId/timeline` | `CatalogItemTimelinePage` | `ItemTimelinePage` | 🟡 |
| 38 | `/catalog/item/:itemId/purchase-history` | `ItemHistoryPage` | `ItemHistoryPage` | 🟡 |
| 39 | `/catalog/item/:itemId/ledger` | `TradeLedgerPage` | `TradeLedgerPage` | 🟡 |
| 40 | `/catalog/category/:categoryId` | `CatalogCategoryDetailPage` | `CategoryDetailPage` | 🟡 |
| 41 | `/catalog/category/:categoryId/type/:typeId` | `CatalogTypeItemsPage` | `TypeItemsPage` | 🟡 |
| 42 | `/catalog/duplicates` | `CatalogDuplicatesPage` | `DuplicatesPage` | 🟡 |
| 43 | `/catalog/item/create` | redirect → `/catalog/quick-add` | `<Navigate to="/catalog/quick-add">` | 🔄 |

---

## 6. Barcode / Scanning (6 routes)

| # | Path | Flutter Widget | React Component | Status |
|---|------|---------------|-----------------|--------|
| 44 | `/barcode/scan` | `BarcodeScanPage` | `BarcodeScanPage` | 🟡 |
| 45 | `/barcode/scan-history` | `BarcodeScanHistoryPage` | `ScanHistoryPage` | 🟡 |
| 46 | `/barcode/audit-session` | `StockAuditSessionPage` | `AuditSessionPage` | 🟡 |
| 47 | `/barcode/audit-summary` | `StockAuditSummaryPage` | `AuditSummaryPage` | 🟡 |
| 48 | `/barcode/print/:itemId` | `BarcodePrintPage` | `BarcodePrintPage` | 🟡 |
| 49 | `/barcode/bulk-print` | `BulkBarcodePrintPage` | `BulkBarcodePrintPage` | 🟡 |

---

## 7. Stock (7 routes + redirects)

| # | Path | Flutter Widget | React Component | Status |
|---|------|---------------|-----------------|--------|
| 50 | `/stock/reorder` | `ReorderListPage` | `ReorderListPage` | 🟡 |
| 51 | `/stock/opening-setup` | `OpeningStockSetupPage` | `OpeningStockSetupPage` | 🟡 |
| 52 | `/stock/staff-purchases` | `StaffPurchaseLogsPage` | `StaffPurchaseLogsPage` | 🟡 |
| 53 | `/stock/low-stock` | `LowStockDashboardPage` | `LowStockDashboardPage` | 🟡 |
| 54 | `/stock/missing-barcodes` | `StockMissingLabelsPage` | `MissingLabelsPage` | 🟡 |
| 55–62 | `/stock/redirects/*` | Various | Various Navigate | 🔄 |

---

## 8. Trade Purchase (4 routes)

| # | Path | Flutter Widget | React Component | Status |
|---|------|---------------|-----------------|--------|
| 61 | `/purchase/new` | `PurchaseEntryWizardV2` | `PurchaseNewPage` | 🟡 |
| 62–63 | `/purchase/scan`, `/purchase/scan-draft` | redirect → `/purchase/new` | Navigate | 🔄 |
| 64 | `/purchase/edit/:purchaseId` | `PurchaseEntryWizardV2` (edit) | `PurchaseEditPage` | 🟡 |
| 65 | `/purchase/detail/:purchaseId` | `PurchaseDetailPage` | `PurchaseDetailPage` | 🟡 |

---

## 9. Supplier (4 routes)

| # | Path | Flutter Widget | React Component | Status |
|---|------|---------------|-----------------|--------|
| 66 | `/supplier/:supplierId` | `SupplierDetailPage` | `SupplierDetailPage` | 🟡 |
| 67 | `/supplier/:supplierId/ledger` | `SupplierLedgerPage` | `SupplierLedgerPage` | 🟡 |
| 68 | `/supplier/:supplierId/batch-items` | `BatchItemCreatePage` | `BatchItemCreatePage` | 🟡 |
| 69 | `/suppliers/quick-create` | `SupplierCreateSimple` | `SupplierQuickCreatePage` | 🟡 |

---

## 10. Broker (3 routes)

| # | Path | Flutter Widget | React Component | Status |
|---|------|---------------|-----------------|--------|
| 70 | `/broker/:brokerId` | `BrokerDetailPage` | `BrokerDetailPage` | 🟡 |
| 71 | `/broker/:brokerId/ledger` | `BrokerHistoryPage` | `BrokerHistoryPage` | 🟡 |
| 72 | `/brokers/quick-create` | `BrokerWizardPage` | `BrokerWizardPage` | 🟡 |

---

## 11. Reports (3 routes)

| # | Path | Flutter Widget | React Component | Status |
|---|------|---------------|-----------------|--------|
| 73 | `/reports/item/:catalogItemId` | `ReportsItemReportPage` | `ItemReportPage` | 🟡 |
| 74 | `/reports/purchase/:purchaseId` | `ReportsPurchaseReportPage` | `PurchaseReportPage` | 🟡 |
| 75 | `/reports/item-detail` | `ReportsItemReportFallbackPage` | `ItemReportFallbackPage` | 🟡 |

---

## 12. Settings (6 routes)

| # | Path | Flutter Widget | React Component | Status |
|---|------|---------------|-----------------|--------|
| 77 | `/settings` | `SettingsPage` | `SettingsPage` | 🟡 |
| 78 | `/settings/business` | `BusinessProfilePage` | `BusinessProfilePage` | 🟡 |
| 79 | `/settings/backup` | `BackupPage` | `BackupPage` | 🟡 |
| 80 | `/settings/help` | `HelpGuidePage` | `HelpGuidePage` | 🟡 |
| 81 | `/settings/users` | `UserManagementPage` | `UserManagementPage` | 🟡 |
| 82 | `/settings/users/:userId` | `UserProfilePage` | `UserProfilePage` | 🟡 |

---

## 13. Staff-specific (8 routes)

| # | Path | Flutter Widget | React Component | Status |
|---|------|---------------|-----------------|--------|
| 83 | `/staff/receive` | `StaffPendingDeliveriesPage` | `StaffReceivePage` | 🟡 |
| 84 | `/staff/receive/:purchaseId` | `StaffReceiveShipmentPage` | `StaffReceiveShipmentPage` | 🟡 |
| 85 | `/staff/low-stock` | `LowStockDashboardPage` | `StaffLowStockPage` | 🟡 |
| 86 | `/staff/items` | `StaffItemGalleryPage` | `StaffItemsPage` | 🟡 |
| 87 | `/staff/settings` | `SettingsPage` | `StaffSettingsPage` | 🟡 |
| 88 | `/staff/purchase-history` | `StaffPurchaseHistoryPage` | `StaffPurchaseHistoryPage` | 🟡 |
| 89 | `/staff/activity` | `StaffActivityPage` | `StaffActivityPage` | 🟡 |
| 90 | `/staff/purchase-history/:purchaseId` | `StaffPurchaseOrderDetailPage` | `StaffPurchaseOrderDetailPage` | 🟡 |

---

## 14. Notifications & Operations (4 routes)

| # | Path | Flutter Widget | React Component | Status |
|---|------|---------------|-----------------|--------|
| 91 | `/notifications` | `NotificationsPage` | `NotificationsPage` | 🟡 |
| 92 | `/operations/usage` | `DailyUsagePage` | `DailyUsagePage` | 🟡 |
| 93 | `/operations/checklist` | `StaffChecklistPage` | `StaffChecklistPage` | 🟡 |
| 94 | `/operations/owner-tasks` | `OwnerTasksPage` | `OwnerTasksPage` | 🟡 |

---

## 15. Redirects (legacy routes)

| # | Path | React Action | Status |
|---|------|-------------|--------|
| 95 | `/dashboard` | → `/home` | 🔄 |
| 96 | `/history` | → `/purchase` | 🔄 |
| 97 | `/entries` | → `/purchase` | 🔄 |
| 98 | `/analytics` | → `/reports` | 🔄 |
| 99 | `/stock/dead` | → `/reports?tab=stock&section=dead` | 🔄 |
| 100 | `/stock/fast-moving` | → `/reports?tab=stock&section=fast` | 🔄 |
| 101 | `/stock/slow-moving` | → `/reports?tab=stock&section=slow` | 🔄 |

---

## Summary

| Category | Total | ✅ | 🟡 | 🔄 | ❌ |
|----------|-------|---|---|----|----|
| Public | 8 | 6 | 1 | 1 | 0 |
| Owner Shell | 7 | 0 | 7 | 0 | 0 |
| Staff Shell | 7 | 0 | 5 | 0 | 1 |
| Contacts | 3 | 0 | 3 | 0 | 0 |
| Catalog | 18 | 0 | 17 | 1 | 0 |
| Barcode | 6 | 0 | 6 | 0 | 0 |
| Stock | 12 | 0 | 5 | 7 | 0 |
| Purchase | 5 | 0 | 3 | 2 | 0 |
| Supplier | 4 | 0 | 4 | 0 | 0 |
| Broker | 3 | 0 | 3 | 0 | 0 |
| Reports | 3 | 0 | 3 | 0 | 0 |
| Settings | 6 | 0 | 6 | 0 | 0 |
| Staff Extras | 8 | 0 | 8 | 0 | 0 |
| Notifications/Ops | 4 | 0 | 4 | 0 | 0 |
| Redirects | 7 | 0 | 0 | 7 | 0 |
| **Total** | **101** | **6** | **75** | **18** | **1** |

**Missing route:** `/staff/stock/changes` — redirect → `/staff/stock?tab=changes`.

**Fully implemented:** 6/101 routes (Splash, Login, ForgotPassword, ResetPassword, redirects).
**Stubs needing implementation:** 75 routes.
