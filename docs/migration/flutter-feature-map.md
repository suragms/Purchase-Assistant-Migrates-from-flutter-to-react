# Flutter Feature Map — Harisree Warehouse App

App name: `harisree_warehouse` (v0.1.4+5)
Framework: Flutter 3.3+, Riverpod + GoRouter + Dio + Hive

---

## Route Tree (from `app_router.dart`)

```
/splash                                    → SplashPage
/login                                     → LoginPage
/forgot-password                           → ForgotPasswordPage
/reset-password?token=                     → ResetPasswordPage
/get-started                               → redirect → /login
/dashboard                                 → redirect → /home
/history                                   → redirect → /purchase
/entries                                   → redirect → /purchase
/analytics                                 → redirect → /reports
/contacts?tab=                             → ContactsPage
/catalog                                   → CatalogPage
/catalog/item/create                       → redirect → /catalog/quick-add
/scan/:token                               → redirect to /item/:lookupKey
/item/:lookupKey                           → PublicItemScanPage
/item-analytics/:itemKey                   → ItemAnalyticsRedirectPage

=== Owner Shell (StatefulShellRoute.indexedStack) ===
  /home                                    → HomePage (ShellBranch.home)
    /home/activity                         → HomeWarehouseActivityPage
    /home/breakdown-more?tab=              → HomeBreakdownListPage
  /stock                                   → StockPage (ShellBranch.stock)
  /reports                                 → FullReportsPage (ShellBranch.reports)
  /purchase                                → PurchaseHomePage (ShellBranch.history)
  /search                                  → SearchPage (ShellBranch.search)

=== Staff Shell (StatefulShellRoute.indexedStack) ===
  /staff/home                              → StaffHomePage
  /staff/stock                             → StockPage (staff mode)
  /staff/scan                              → BarcodeScanPage
  /staff/search                            → SearchPage (staff)
  /staff/deliveries                        → StaffPendingDeliveriesPage
  /staff/tasks                             → StaffChecklistPage

=== Detail / Modal routes (outside shell) ===
  /catalog/item/:itemId                    → ItemDetailPage
  /catalog/item/:itemId/edit               → ItemEditPage
  /catalog/item/:itemId/timeline           → CatalogItemTimelinePage
  /catalog/quick-add                       → CatalogItemCreatePage
  /catalog/quick-add-from-scan?barcode=    → BarcodeQuickCreatePage
  /catalog/taxonomy                        → CatalogTaxonomyHubPage
  /catalog/new-category                    → CatalogAddCategoryPage
  /catalog/category/:id                    → CatalogCategoryDetailPage
  /catalog/category/:id/type/:tid          → CatalogTypeItemsPage
  /catalog/category/:id/new-subcategory    → CatalogAddSubcategoryPage
  /catalog/category/:id/type/:tid/add-item → CatalogAddItemPage
  /catalog/duplicates                      → CatalogDuplicatesPage
  /catalog/setup-reorder-levels            → CatalogSetupReorderLevelsPage
  /catalog/missing-codes                   → CatalogMissingCodesPage
  /catalog/item/:itemId/purchase-history   → ItemHistoryPage
  /catalog/item/:itemId/ledger             → TradeLedgerPage
  /barcode/scan                            → BarcodeScanPage
  /barcode/scan-history                    → BarcodeScanHistoryPage
  /barcode/audit-session                   → StockAuditSessionPage
  /barcode/audit-summary                   → StockAuditSummaryPage
  /barcode/print/:itemId                   → BarcodePrintPage
  /barcode/bulk-print                      → BulkBarcodePrintPage
  /stock/reorder                           → ReorderListPage
  /stock/reorder-suggestions               → redirect → /stock/reorder
  /stock/opening-setup                     → OpeningStockSetupPage
  /stock/low-stock                         → LowStockDashboardPage
  /stock/staff-purchases                   → StaffPurchaseLogsPage
  /stock/missing-barcodes                  → StockMissingLabelsPage
  /stock/movement                          → redirect → /stock?tab=movement
  /stock/changes                           → redirect → /stock?tab=changes
  /stock/today-feed                        → redirect → /stock?tab=today
  /stock/dead                              → redirect → /reports?tab=stock&section=dead
  /stock/fast-moving                       → redirect → /reports?tab=stock&section=fast
  /stock/slow-moving                       → redirect → /reports?tab=stock&section=slow
  /stock/intelligence/:itemId              → redirect → /catalog/item/:id?source=intelligence
  /stock/:itemId/history                   → redirect → /catalog/item/:id?tab=history
  /purchase/new                            → PurchaseEntryWizardV2
  /purchase/edit/:purchaseId               → PurchaseEntryWizardV2
  /purchase/detail/:purchaseId             → PurchaseDetailPage
  /settings                                → SettingsPage
  /settings/business                       → BusinessProfilePage
  /settings/backup                         → BackupPage
  /settings/help                           → HelpGuidePage
  /settings/users                          → UserManagementPage
  /settings/users/:userId                  → UserProfilePage
  /contacts/supplier/new                   → SupplierCreateSimple
  /supplier/:supplierId                    → SupplierDetailPage
  /supplier/:supplierId/ledger             → SupplierLedgerPage
  /supplier/:supplierId/batch-items        → BatchItemCreatePage
  /suppliers/quick-create                  → SupplierCreateSimple
  /broker/:brokerId                        → BrokerDetailPage
  /broker/:brokerId/ledger                 → BrokerHistoryPage
  /brokers/quick-create                    → BrokerWizardPage
  /contacts/category?name=                 → CategoryItemsPage
  /notifications                           → NotificationsPage
  /operations/usage                        → DailyUsagePage
  /operations/checklist                    → StaffChecklistPage
  /operations/owner-tasks                  → OwnerTasksPage
  /reports/item/:catalogItemId             → ReportsItemReportPage
  /reports/item-detail                     → ReportsItemReportFallbackPage
  /reports/purchase/:purchaseId            → ReportsPurchaseReportPage
  /staff/receive                           → StaffPendingDeliveriesPage
  /staff/receive/:purchaseId               → StaffReceiveShipmentPage
  /staff/stock/changes                     → redirect → /staff/stock?tab=changes
  /staff/receive/:purchaseId               → StaffReceiveShipmentPage
  /staff/low-stock                         → LowStockDashboardPage (staff)
  /staff/items                             → StaffItemGalleryPage
  /staff/settings                          → SettingsPage
  /staff/purchase-history                  → StaffPurchaseHistoryPage
  /staff/purchase-history/:purchaseId      → StaffPurchaseOrderDetailPage
  /staff/activity                          → StaffActivityPage
```

---

## Feature Directory Breakdown

### 1. Auth (`features/auth/`)

**Screens/Routes:**
- `LoginPage` (`/login`) — email/password login, Google sign-in tab
- `ForgotPasswordPage` (`/forgot-password`)
- `ResetPasswordPage` (`/reset-password?token=`)

**Riverpod Providers (from `core/providers/`):**
- `sessionProvider` — `StateNotifierProvider<SessionNotifier, UserSession?>` — auth state
- `authSessionExpiredProvider` — checks JWT expiry
- `auth401CircuitOpenProvider` — circuit breaker for 401 responses
- Prefs: `prefsProvider` — stores selected business ID, user prefs

**API Endpoints Called:**
- `POST /v1/auth/login`
- `POST /v1/auth/google`
- `POST /v1/auth/refresh`
- `POST /v1/auth/register`
- `POST /v1/auth/forgot-password`
- `POST /v1/auth/reset-password`

**Client Business Logic:**
- Token storage via `flutter_secure_storage` (`core/auth/token_store.dart`)
- Biometric auth gate (`core/auth/biometric_auth.dart`)
- JWT decode + expiry check (`core/auth/session_notifier.dart`)
- Circuit breaker on 401 responses (`core/auth/auth_failure_policy.dart`)

---

### 2. Splash (`features/splash/`)

**Screens/Routes:** `SplashPage` (`/splash`)

**Providers:** `sessionProvider` (reads stored token)

**Logic:** On init: tries to restore JWT from secure storage → if valid, redirect to `/home`; if expired, attempt refresh or redirect to `/login`.

---

### 3. Shell (`features/shell/`)

**Screens/Routes:**
- `ShellScreen` — owner bottom nav shell (5 tabs: Home, Stock, Reports, Purchase, Search)
- `StaffShellScreen` — staff bottom nav shell (6 tabs: Home, Stock, Scan, Search, Deliveries, Tasks)

**Providers:**
- `shellBranchProvider` — tracks active branch index
- Active business + session providers

---

### 4. Home/Dashboard (`features/home/`)

**Screens/Routes:**
- `HomePage` (`/home`) — dashboard with KPI cards, charts, recent activity
- `HomeWarehouseActivityPage` (`/home/activity`) — live activity feed
- `HomeBreakdownListPage` (`/home/breakdown-more?tab=`) — full category/item breakdown

**Providers (from `core/providers/`):**
- `homeDashboardProvider` — fetches `/v1/businesses/{id}/dashboard?month=YYYY-MM`
- `homeBreakdownTabProvider` — tab state for breakdown
- `homeOperationalBundleProvider` — fetches operational stats
- `businessAggregatesInvalidationProvider` — invalidation triggers

**API Endpoints Called:**
- `GET /v1/businesses/{id}/dashboard?month=`
- `GET /v1/businesses/{id}/users/{uid}/today-stats` (via user services)
- `GET /v1/businesses/{id}/contacts/category-items?category=&from=&to=`
- `GET /v1/businesses/{id}/stock/summary`

**Client Business Logic:**
- Period selection (month picker)
- Category heuristic splitting for dashboard grouping
- Spending ring diameter calculation (`home_spend_ring_diameter.dart`)
- Low stock / warehouse alerts aggregation

---

### 5. Catalog (`features/catalog/`)

**Screens/Routes:**
- `CatalogPage` (`/catalog`) — full catalog with category/type tree
- `CatalogTaxonomyHubPage` (`/catalog/taxonomy`) — manage categories + types
- `CatalogAddCategoryPage` (`/catalog/new-category`)
- `CatalogAddSubcategoryPage` (`/catalog/category/:id/new-subcategory`)
- `CatalogCategoryDetailPage` (`/catalog/category/:id`) — items in category
- `CatalogTypeItemsPage` (`/catalog/category/:id/type/:tid`) — items in type
- `CatalogItemCreatePage` (`/catalog/quick-add`) — wizard for adding items
- `CatalogAddItemPage` — add to specific category/type
- `CatalogItemTimelinePage` (`/catalog/item/:id/timeline`) — price history
- `CatalogDuplicatesPage` (`/catalog/duplicates`) — fuzzy match review
- `CatalogMissingCodesPage` (`/catalog/missing-codes`) — items without ITM codes
- `CatalogSetupReorderLevelsPage` (`/catalog/setup-reorder-levels`)
- `BarcodeQuickCreatePage` — create from scanned barcode
- `ItemDetailPage` (`/catalog/item/:id`) — full item detail
- `ItemEditPage` (`/catalog/item/:id/edit`) — edit item
- `BatchItemCreatePage` (`/supplier/:id/batch-items`) — batch add

**Providers (from `core/providers/`):**
- `catalogItemsProvider` — paginated item list with caching via `catalog_items_list_cache_key`
- `catalogItemDetailProvider` — single item detail
- `catalogCategoriesProvider` — categories list
- `catalogCategoryTypesProvider` — types for a category
- `catalogFuzzyCheckProvider` — debounced fuzzy duplicate check
- `catalogItemInsightsProvider` — item profit/price insights
- `catalogItemLinesProvider` — item purchase history lines
- `catalogDuplicatesProvider`
- `catalogItemTradeSupplierPricesProvider`

**API Endpoints Called:**
- `GET /v1/businesses/{id}/catalog-items` (with filters)
- `GET /v1/businesses/{id}/catalog-items/{item_id}`
- `POST /v1/businesses/{id}/catalog-items`
- `POST /v1/businesses/{id}/catalog-items/from-scan`
- `POST /v1/businesses/{id}/catalog-items/batch`
- `PATCH /v1/businesses/{id}/catalog-items/{item_id}/item-code`
- `PATCH /v1/businesses/{id}/catalog-items/{item_id}/barcode`
- `POST /v1/businesses/{id}/catalog-items/{item_id}/generate-code`
- `GET /v1/businesses/{id}/catalog-items/{item_id}/insights?from=&to=`
- `GET /v1/businesses/{id}/catalog-items/{item_id}/lines?from=&to=`
- `GET /v1/businesses/{id}/catalog-items/{item_id}/trade-supplier-prices`
- `GET /v1/businesses/{id}/catalog-items/{item_id}/supplier-purchase-defaults?supplier_id=`
- `GET /v1/businesses/{id}/item-categories`
- `POST /v1/businesses/{id}/item-categories`
- `GET /v1/businesses/{id}/item-categories/{id}`
- `PATCH /v1/businesses/{id}/item-categories/{id}`
- `DELETE /v1/businesses/{id}/item-categories/{id}`
- `GET /v1/businesses/{id}/item-categories/{id}/category-types`
- `POST /v1/businesses/{id}/item-categories/{id}/category-types`
- `PATCH /v1/businesses/{id}/item-categories/{id}/category-types/{type_id}`
- `DELETE /v1/businesses/{id}/item-categories/{id}/category-types/{type_id}`
- `GET /v1/businesses/{id}/category-types-index`
- `GET /v1/businesses/{id}/catalog/fuzzy-check`
- `GET /v1/businesses/{id}/catalog/duplicate-clusters`
- `POST /v1/businesses/{id}/catalog/items/bulk-archive`
- `PATCH /v1/businesses/{id}/catalog/items/bulk-reorder`

**Client Business Logic:**
- Unit conversion labels via `core/units/` (dynamic unit labels, resolved unit context)
- Category/type tree navigation
- Fuzzy duplicate prevention before create
- Barcode normalization
- Item code auto-generation (ITM-NNNN display)

---

### 6. Stock (`features/stock/`)

**Screens/Routes:**
- `StockPage` (`/stock`, `/staff/stock`) — full stock list with tabs (all, low stock, movements, changes, physical counts)
- `ReorderListPage` (`/stock/reorder`) — items below reorder level
- `OpeningStockSetupPage` (`/stock/opening-setup`) — initial stock entry
- `LowStockDashboardPage` (`/stock/low-stock`, `/staff/low-stock`)
- `StockMissingLabelsPage` (`/stock/missing-barcodes`)
- `StaffPurchaseLogsPage` (`/stock/staff-purchases`)
- `StockItemIntelligencePage` — item-level stock intelligence
- `UpdateStockSheet` / `QuickStockActionSheet` — bottom sheets for adjust/move
- `StockQuickPurchaseSheet` — quick purchase from stock

**Providers (from `core/providers/`):**
- `stockListProvider` — paginated stock list with cache
- `stockListExceptionsProvider` — error handling
- `stockOfflineQueueProvider` — offline queue for stock adjustments
- `lowStockProvider` — low stock items
- `lowStockPriorityProvider` — prioritized low stock list
- `reorderListProvider` — reorder suggestions
- `stockMovementProvider` — movement history
- `stockPhysicalCountProvider` — physical count records
- `stockAuditSessionsProvider` — audit session list

**API Endpoints Called:**
- `GET /v1/businesses/{id}/stock`
- `GET /v1/businesses/{id}/stock/summary`
- `POST /v1/businesses/{id}/stock/adjust`
- `POST /v1/businesses/{id}/stock/move`
- `GET /v1/businesses/{id}/stock/movements?item_id=`
- `POST /v1/businesses/{id}/stock/physical-count`
- `GET /v1/businesses/{id}/stock/physical-counts`
- `GET /v1/businesses/{id}/stock/reorder-list`
- `POST /v1/businesses/{id}/stock-audits`
- `GET /v1/businesses/{id}/stock-audits`

**Client Business Logic:**
- Stock save recovery (`core/stock/save_recovery.dart`) — optimistic updates + rollback
- Version retry on stale stock (`core/stock/version_retry.dart`)
- Stock movement unit mismatch detection
- Offline queue for adjustments when network unavailable
- Stock undo via snackbar (`stock_undo_snackbar.dart`)

---

### 7. Purchase (`features/purchase/`)

**Screens/Routes:**
- `PurchaseHomePage` (`/purchase`) — purchase list with filters (status, date, supplier)
- `PurchaseDetailPage` (`/purchase/detail/:id`) — full purchase detail with lines
- `PurchaseEntryWizardV2` (`/purchase/new`, `/purchase/edit/:id`) — multi-step purchase wizard

**Sub-folders:**
- `domain/` — `PurchaseDraft` model, draft serialization
- `mapping/` — Maps API response to UI models
- `pricing/` — Tax mode computation, line totals
- `providers/` — Purchase-specific Riverpod providers
- `presentation/` — Screens + widgets
- `state/` — Wizard state machine
- `wizard/` — Wizard step widgets

**Providers (from `core/providers/`):**
- `tradePurchasesProvider` — paginated purchase list with cache
- `tradePurchasesListInflightProvider` — in-flight purchase operations
- `tradePurchaseDetailProvider` — single purchase detail
- `purchasePostSaveProvider` — post-save operations
- `purchasePrefillProvider` — last-purchase defaults prefill
- `purchaseDamageReportsProvider` — damage reports for purchase
- `deliveryPipelineProvider` — delivery pipeline state
- `tradeReportSnapshotProvider` — trade report cache generation

**API Endpoints Called:**
- `GET /v1/businesses/{id}/trade-purchases?limit=&offset=&status=&q=&supplier_id=&broker_id=&purchase_from=&purchase_to=&include_lines=`
- `GET /v1/businesses/{id}/trade-purchases/{purchase_id}`
- `POST /v1/businesses/{id}/trade-purchases`
- `PUT /v1/businesses/{id}/trade-purchases/{purchase_id}`
- `DELETE /v1/businesses/{id}/trade-purchases/{purchase_id}`
- `GET /v1/businesses/{id}/trade-purchases/draft`
- `PUT /v1/businesses/{id}/trade-purchases/draft`
- `DELETE /v1/businesses/{id}/trade-purchases/draft`
- `POST /v1/businesses/{id}/trade-purchases/preview-lines`
- `POST /v1/businesses/{id}/trade-purchases/validate`
- `POST /v1/businesses/{id}/trade-purchases/check-duplicate`
- `GET /v1/businesses/{id}/trade-purchases/next-human-id`
- `GET /v1/businesses/{id}/trade-purchases/last-defaults`
- `PATCH /v1/businesses/{id}/trade-purchases/{purchase_id}/payment`
- `POST /v1/businesses/{id}/trade-purchases/{purchase_id}/mark-paid`
- `POST /v1/businesses/{id}/trade-purchases/{purchase_id}/cancel`
- `PATCH /v1/businesses/{id}/trade-purchases/{purchase_id}/delivery`
- `POST /v1/businesses/{id}/trade-purchases/{purchase_id}/dispatch`
- `POST /v1/businesses/{id}/trade-purchases/{purchase_id}/arrive`
- `POST /v1/businesses/{id}/trade-purchases/{purchase_id}/commit-stock`
- `POST /v1/businesses/{id}/trade-purchases/{purchase_id}/auto-commit`
- `POST /v1/businesses/{id}/trade-purchases/{purchase_id}/verify`
- `GET /v1/businesses/{id}/trade-purchases/delivery-pipeline`
- `GET /v1/businesses/{id}/trade-purchases/{purchase_id}/lifecycle-events`
- `POST /v1/businesses/{id}/trade-purchases/{purchase_id}/lifecycle`
- `POST /v1/businesses/{id}/trade-purchases/{purchase_id}/damage-reports`
- `GET /v1/businesses/{id}/trade-purchases/{purchase_id}/damage-reports`

**Client Business Logic:**
- Purchase wizard state machine (5 steps: supplier → items → pricing → review → submit)
- Draft auto-save (local storage + server draft)
- Line total computation (qty × landing_cost, tax mode handling via `core/pricing/tax_mode.dart`)
- Duplicate detection before create
- Purchase unit validation (`core/purchase_unit_warning.dart`)
- Draft resume on app restart

---

### 8. Reports (`features/reports/`)

**Sub-folders:**
- `shell/` — `FullReportsPage` main reports shell
- `filters/` — Date range, supplier, broker, category filters
- `presentation/` — Report display widgets
- `reporting/` — Data aggregation logic
- `stock/` — Stock reports (dead/slow/fast moving)
- `tabs/` — Report tab content
- `drill/` — Drill-down pages
- `widgets/` — Reusable report widgets

**Screens/Routes:**
- `FullReportsPage` (`/reports`) — tabbed report shell
- `ReportsItemReportPage` (`/reports/item/:id`) — single item BI
- `ReportsPurchaseReportPage` (`/reports/purchase/:id`) — single purchase BI
- `ReportsItemDetailPage` — fallback item detail

**Providers (from `core/providers/`):**
- `reportsProvider` — main report data
- `reportsFilteredProvider` — filtered report data
- `reportsShellProviders` — tab state management
- `reportsItemBundleProvider` — item-level report bundle
- `reportsBiProviders` — BI/analytics providers
- `reportsPriorPeriodProvider` — prior period comparison
- `fullReportsInsightsProviders` — aggregated insights
- `homeDashboardProvider` — month dashboard data

**API Endpoints Called:**
- `GET /v1/businesses/{id}/reports/trade?from=&to=&group_by=&supplier_id=&broker_id=&category_id=&type_id=&catalog_item_id=`
- `GET /v1/businesses/{id}/dashboard?month=`
- `GET /v1/businesses/{id}/reports/saved-views`
- `POST /v1/businesses/{id}/reports/saved-views`
- Data also sourced from catalog items and trade purchases endpoints

**Client Business Logic:**
- Period comparison (current vs prior month/quarter)
- Date range selection and filtering
- Report filter state management
- Chart rendering (fl_chart for bar/line/pie)
- Export trigger (sharesheet for PDF)

---

### 9. Barcode (`features/barcode/`)

**Screens/Routes:**
- `BarcodeScanPage` (`/barcode/scan`, `/staff/scan`) — camera barcode scanner
- `BarcodeScanHistoryPage` (`/barcode/scan-history`) — recent scans
- `BarcodePrintPage` (`/barcode/print/:itemId`) — single barcode label print
- `BulkBarcodePrintPage` (`/barcode/bulk-print`) — batch label print
- `PublicItemScanPage` (`/item/:lookupKey`) — public item view
- `StockAuditSessionPage` (`/barcode/audit-session`) — audit via barcode
- `StockAuditSummaryPage` (`/barcode/audit-summary`) — audit results

**Providers:**
- `barcodeRecentScansProvider` — recent scan history
- `catalogItemByBarcodeProvider` — lookup by barcode

**API Endpoints Called:**
- `GET /v1/businesses/{id}/catalog-items/{item_id}` (after scan)
- `GET /v1/public/items/{public_token}` (public view)
- Stock audit endpoints

**Client Business Logic:**
- Camera integration via `mobile_scanner` / `camera`
- Barcode format detection (EAN-13, CODE-128, QR, etc.)
- Print label generation (PDF via `printing` package)
- Audit session management (count → compare → resolve)

---

### 10. Search (`features/search/`)

**Screens/Routes:**
- `SearchPage` (`/search`, `/staff/search`) — unified search

**Providers:**
- `recentUnifiedSearchProvider` — recent searches
- `contactsSearchProvider` — search contacts/catalog
- `searchFocusProvider` — focus state management

**API Endpoints Called:**
- `GET /v1/businesses/{id}/search?q=&scope=&limit=`
- `GET /v1/businesses/{id}/contacts/search?q=&scope=&limit=`

**Client Business Logic:**
- Debounced search input
- Scope selection (all, suppliers, brokers, items, categories)
- Recent search history persistence

---

### 11. Contacts (`features/contacts/`, `features/supplier/`, `features/broker/`)

**Screens/Routes:**
- `ContactsPage` (`/contacts`) — tabbed supplier/broker list with search
- `SupplierDetailPage` (`/supplier/:id`) — supplier profile + purchases
- `SupplierLedgerPage` (`/supplier/:id/ledger`) — financial ledger
- `SupplierCreateSimple` (`/contacts/supplier/new`) — quick create
- `BrokerDetailPage` (`/broker/:id`) — broker profile
- `BrokerHistoryPage` (`/broker/:id/ledger`) — broker history
- `BrokerWizardPage` (`/brokers/quick-create`) — create broker
- `TradeLedgerPage` — generic trade ledger (item/supplier/broker)
- `CategoryItemsPage` (`/contacts/category?name=`) — category item drill

**Providers (from `core/providers/`):**
- `suppliersListProvider` — cached supplier list
- `brokersListProvider` — cached broker list
- `contactsHubProvider` — hub/aggregate contacts data
- `contactsListFetchProvider` — lazy fetch for contacts
- `supplierDetailProvider`
- `brokerDetailProvider`
- `supplierMetricsProvider`
- `brokerMetricsProvider`

**API Endpoints Called:**
- `GET /v1/businesses/{id}/suppliers?compact=&limit=`
- `POST /v1/businesses/{id}/suppliers`
- `GET /v1/businesses/{id}/suppliers/{supplier_id}`
- `PATCH /v1/businesses/{id}/suppliers/{supplier_id}`
- `DELETE /v1/businesses/{id}/suppliers/{supplier_id}`
- `GET /v1/businesses/{id}/suppliers/{supplier_id}/metrics?from=&to=`
- `GET /v1/businesses/{id}/brokers`
- `POST /v1/businesses/{id}/brokers`
- `GET /v1/businesses/{id}/brokers/{broker_id}`
- `PATCH /v1/businesses/{id}/brokers/{broker_id}`
- `DELETE /v1/businesses/{id}/brokers/{broker_id}`
- `GET /v1/businesses/{id}/brokers/{broker_id}/metrics?from=&to=`
- `GET /v1/businesses/{id}/contacts/search?q=&scope=`

---

### 12. Staff (`features/staff/`)

**Screens/Routes:**
- `StaffHomePage` (`/staff/home`) — staff dashboard
- `StaffPendingDeliveriesPage` (`/staff/deliveries`, `/staff/receive`) — delivery queue
- `StaffReceiveShipmentPage` (`/staff/receive/:purchaseId`) — receive shipment
- `StaffPurchaseHistoryPage` (`/staff/purchase-history`) — staff purchase log
- `StaffPurchaseOrderDetailPage` — order detail
- `StaffActivityPage` (`/staff/activity`) — activity log viewer
- `StaffItemGalleryPage` (`/staff/items`) — item browser
- `StaffShellScreen` — staff bottom nav shell

**Providers (from `core/providers/`):**
- `staffHomeProviders` — staff home data
- `deliveryPipelineProvider` — delivery pipeline
- `activityLogProvider` — staff activity feed
- `lowStockProvider` — low stock alerts

**API Endpoints Called:**
- `GET /v1/businesses/{id}/trade-purchases/delivery-pipeline`
- `POST /v1/businesses/{id}/trade-purchases/{purchase_id}/arrive`
- `POST /v1/businesses/{id}/trade-purchases/{purchase_id}/verify`
- `GET /v1/businesses/{id}/activity-log`
- `POST /v1/businesses/{id}/activity-log`
- `GET /v1/businesses/{id}/stock?low_stock=true`
- `POST /v1/businesses/{id}/stock/physical-count`

**Client Business Logic:**
- Staff-specific navigation guards (only allowed routes)
- Simplified UI for delivery receipt and scanning
- Low stock notification display

---

### 13. Settings (`features/settings/`)

**Screens/Routes:**
- `SettingsPage` (`/settings`) — settings hub
- `BusinessProfilePage` (`/settings/business`) — business branding
- `UserManagementPage` (`/settings/users`) — user CRUD
- `UserProfilePage` (`/settings/users/:userId`) — single user profile/permissions
- `BackupPage` (`/settings/backup`) — export/backup
- `HelpGuidePage` (`/settings/help`) — in-app guide

**Providers:**
- `businessProfileProvider` — business details
- `businessUsersProvider` — user list
- `businessWriteEventProvider` — mutation events
- `businessWriteRevisionProvider` — revision tracking

**API Endpoints Called:**
- `GET /v1/me/businesses`
- `PATCH /v1/me/businesses/{id}/branding`
- `POST /v1/me/businesses/{id}/branding/logo`
- `GET /v1/businesses/{id}/users`
- `POST /v1/businesses/{id}/users`
- `PATCH /v1/businesses/{id}/users/{user_id}`
- `DELETE /v1/businesses/{id}/users/{user_id}`
- `POST /v1/businesses/{id}/users/{user_id}/reset-password`
- `POST /v1/businesses/{id}/users/bulk`
- `GET /v1/businesses/{id}/users/{user_id}/permissions`
- `PATCH /v1/businesses/{id}/users/{user_id}/permissions`
- `POST /v1/businesses/{id}/exports/backup`
- `GET /v1/businesses/{id}/exports/stock-inventory.xlsx`
- `GET /v1/businesses/{id}/exports/backup/export`

**Client Business Logic:**
- User role management UI (role selector, permission toggles)
- Readable password generation display
- Backup/export trigger with progress

---

### 14. Notifications (`features/notifications/`)

**Screens/Routes:**
- `NotificationsPage` (`/notifications`) — notification list

**Providers:**
- `notificationsProvider` — notification list + pagination
- `notificationCenterProvider` — aggregated notification center
- `serverNotificationsProvider` — SSE-driven live notifications
- `unreadCountProvider` — badge count

**API Endpoints Called:**
- `GET /v1/businesses/{id}/notifications?page=&per_page=&kind=&category=&priority=&unread_only=`
- `GET /v1/businesses/{id}/notifications/summary`
- `GET /v1/businesses/{id}/notifications/unread-count`
- `PATCH /v1/businesses/{id}/notifications/{notification_id}`
- `POST /v1/businesses/{id}/notifications/mark-all-read`
- `DELETE /v1/businesses/{id}/notifications/clear-all`

**Client Business Logic:**
- Unread badge on shell tab
- Notification read/unread state management
- SSE event listener for real-time notification arrival

---

### 15. Operations (`features/operations/`)

**Screens/Routes:**
- `DailyUsagePage` (`/operations/usage`) — log daily item usage
- `StaffChecklistPage` (`/operations/checklist`, `/staff/tasks`) — checklist completion
- `OwnerTasksPage` (`/operations/owner-tasks`) — owner task overview

**Providers:**
- `operationsProviders` — daily usage + checklist providers

**API Endpoints Called:**
- `GET /v1/businesses/{id}/operations/daily-usage`
- `POST /v1/businesses/{id}/operations/daily-usage`
- `GET /v1/businesses/{id}/operations/checklists`
- `POST /v1/businesses/{id}/operations/checklists/completions`
- `GET /v1/businesses/{id}/operations/checklists/completions`

---

### 16. Item (`features/item/`)

**Screens/Routes:**
- `ItemHistoryPage` (`/catalog/item/:id/purchase-history`) — purchase history for item
- `ItemAnalyticsRedirectPage` (`/item-analytics/:itemKey`) — redirect to item BI

---

### 17. Core Business Logic (`core/`)

| Module | File(s) | Purpose |
|--------|---------|---------|
| `core/calc_engine.dart` | 1 | Numeric aggregations (line totals, profit, margins) |
| `core/strict_decimal.dart` | 1 | Decimal arithmetic with rounding rules |
| `core/purchase_unit_warning.dart` | 1 | Detects unit mismatches between purchase lines and catalog items |
| `core/pricing/tax_mode.dart` | 1 | Tax-inclusive vs exclusive price computation |
| `core/units/dynamic_unit_labels.dart` | 1 | Human-readable unit labels (PC, PCS, BAG, KG, etc.) |
| `core/units/resolved_unit_context.dart` | 1 | Unit resolution context from catalog item profiles |
| `core/decision/trade_buy_verdict.dart` | 1 | AI-pricing decision logic: recommends buy/hold based on last 3 prices + trend |
| `core/catalog/item_trade_history.dart` | 1 | Catalog item trade history helpers |
| `core/stock/save_recovery.dart` | 1 | Optimistic stock save with rollback on failure |
| `core/stock/version_retry.dart` | 1 | Retry stock operations on version conflict (409) |
| `core/services/` | 33 | PDF generation, backup/export, offline sync, Hive storage, notification scheduling |
| `core/notifications/` | 2 | Local notification scheduling + post-login prompt |
| `core/platform/` | 12 | Foreground detection, quick actions, boot overlay, reload triggers |
| `core/providers/` | 55 | All Riverpod providers (see table below) |
| `core/widgets/` | 17 | Reusable widgets (deferred loader, error cards, async buttons, metric cards) |
| `core/design_system/` | 13 | Design tokens, theme, responsive helpers |

**Key Riverpod Providers (55 files):**

| File | Key Providers | Used In |
|------|---------------|---------|
| `analytics_breakdown_providers.dart` | Analytics breakdown/aggregation | Reports |
| `analytics_kpi_provider.dart` | `analyticsDateRangeProvider`, KPI state | Reports |
| `api_degraded_provider.dart` | `apiDegradedProvider` — global degradation hint | Core |
| `api_health_snapshot_provider.dart` | `apiHealthSnapshotProvider` — health probes | Core / Splash |
| `api_read_snapshots.dart` | `stockAuditRecentSnapshotProvider`, trade recent snapshots | Home / Stock / Activity |
| `app_period_provider.dart` | `appPeriodDateRange` | Home / Reports |
| `barcode_recent_scans.dart` | Recent scan history | Barcode |
| `brokers_list_provider.dart` | Cached broker list | Contacts |
| `business_aggregates_invalidation.dart` | Invalidation triggers | Home |
| `business_profile_provider.dart` | Business details | Settings |
| `business_users_provider.dart` | User list | Settings |
| `business_write_event.dart` | Mutation events | Settings |
| `business_write_revision.dart` | Revision tracking | Settings |
| `catalog_providers.dart` | `catalogItemsProvider`, `catalogItemDetailProvider`, categories, types, fuzzy check, insights, lines, duplicates | Catalog |
| `connectivity_provider.dart` | `connectivityResultsProvider` — offline banner | Core |
| `contacts_hub_provider.dart` | Hub/aggregate contacts data | Contacts |
| `contacts_list_fetch.dart` | Lazy fetch for contacts | Contacts |
| `dashboard_period_provider.dart` | `dashboardPeriodProvider` — period enum | Home / Dashboard |
| `deferred_invalidation.dart` | `deferInvalidate` — post-frame invalidation helper | Core |
| `delivery_pipeline_provider.dart` | Delivery pipeline state | Staff / Purchase |
| `full_reports_insights_providers.dart` | Aggregated insights | Reports |
| `home_breakdown_tab_providers.dart` | Tab state for breakdown | Home |
| `home_dashboard_provider.dart` | Month dashboard data | Home |
| `home_owner_dashboard_providers.dart` | Owner dashboard data (922 lines) | Home |
| `item_detail_providers.dart` | Item detail + stock bundle + intelligence | Catalog / Stock |
| `low_stock_providers.dart` | Low stock items + priority | Stock |
| `notification_center_provider.dart` | Aggregated notification center | Notifications |
| `notifications_provider.dart` | Notification list + pagination | Notifications |
| `operations_providers.dart` | Daily usage + checklist | Operations |
| `prefs_provider.dart` | Selected business ID, user prefs | Core |
| `provider_helpers.dart` | Shared provider utilities | Core |
| `purchase_damage_reports_provider.dart` | Damage reports for purchase | Purchase |
| `purchase_post_save_provider.dart` | Post-save operations | Purchase |
| `purchase_prefill_provider.dart` | Last-purchase defaults prefill | Purchase |
| `realtime_events_provider.dart` | `invalidateAfterStockWrite`, SSE real-time refresh | Stock / Purchase |
| `recent_unified_search_provider.dart` | Recent searches | Search |
| `reorder_list_provider.dart` | Reorder suggestions | Stock |
| `reports_bi_providers.dart` | BI/analytics providers | Reports |
| `reports_filtered_provider.dart` | Filtered report data | Reports |
| `reports_item_bundle_provider.dart` | Item-level report bundle | Reports |
| `reports_prior_period_provider.dart` | Prior period comparison | Reports |
| `reports_provider.dart` | Main report data | Reports |
| `reports_shell_providers.dart` | Tab state management | Reports |
| `search_focus_provider.dart` | Focus state management | Search |
| `server_notifications_provider.dart` | SSE-driven live notifications | Notifications |
| `staff_home_providers.dart` | Staff home data | Staff |
| `stock_audit_providers.dart` | `activeStockAuditProvider`, `stockAuditKpisProvider` | Barcode / Audit |
| `stock_list_exceptions.dart` | Error handling | Stock |
| `stock_offline_queue_provider.dart` | Offline queue for stock adjustments | Stock |
| `stock_providers.dart` | Stock list, movements, physical counts | Stock |
| `suppliers_list_provider.dart` | Cached supplier list | Contacts |
| `trade_purchases_list_inflight.dart` | In-flight purchase operations | Purchase |
| `trade_purchases_provider.dart` | Paginated purchase list with cache | Purchase |
| `trade_report_snapshot_provider.dart` | Trade report cache generation | Purchase |
| `warehouse_alerts_provider.dart` | Consolidated alert counts | Home / Stock |

**Staff shell branch provider (outside core/providers/):**
`features/staff/staff_shell_branch_provider.dart` — defines `staffShellCurrentBranchProvider`

**Key Business Logic Details:**

- **Unit Conversion Engine** (`core/units/`): Maps between 5 canonical units (BAG, KG, BOX, TIN, PIECE) and display variants (BAG/SACK, PIECE/PC/PCS, LOOSE/KG). Used in purchase wizard, stock display, and reports.

- **Trade Buy Verdict** (`core/decision/trade_buy_verdict.dart`): Analyzes last 3 purchase prices for an item from `CatalogItemTradeSupplierPricesOut` to determine if current price is a good deal. Returns verdict: `buy`, `hold`, or `neutral` with reasoning.

- **Tax Mode** (`core/pricing/tax_mode.dart`): Computes line total correctly for both `inclusive` (GST included in price) and `exclusive` (GST added on top) tax modes.

- **Error Handling** (`core/errors/`): User-facing error messages for barcode errors, stock version conflicts, network failures. Load state management with retry capabilities.

- **Offline Support**: `stock_offline_queue_provider.dart` queues stock adjustments when offline. `core/services/` includes Hive-based local storage for offline catalog and recent purchases.

---

## Notes on Incomplete/Empty Feature Directories

The following directories exist but appear empty or contain only placeholder files:
- `features/admin/` — empty (not implemented)
- `features/analytics/` — empty (subsumed by reports)
- `features/assistant/` — empty (AI assistant planned)
- `features/dashboard/` — legacy alias (re-exports `home/presentation/home_page.dart`); route `/dashboard` redirects to `/home`
- `features/entries/` — empty (legacy redirects to purchase)
- `features/get_started/` — empty (redirects to login)
- `features/voice/` — empty (voice input planned)
