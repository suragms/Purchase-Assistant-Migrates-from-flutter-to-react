import { createBrowserRouter, Navigate } from "react-router-dom";
import { AuthGuard } from "./components/guards/AuthGuard";
import { OwnerAppShell } from "./features/shell/OwnerAppShell";
import { StaffAppShell } from "./features/shell/StaffAppShell";
import { MigratedRoutePage } from "./pages/migrated/MigratedRoutePage";

// Public routes (direct imports so they're eager — splash/login must load fast)
import SplashPage from "./pages/auth/SplashPage";
import LoginPage from "./pages/auth/LoginPage";
import ResetPasswordPage from "./pages/auth/ResetPasswordPage";

const ForgotPasswordPage = () =>
  import("./features/auth/pages/ForgotPasswordPage").then((m) => ({
    Component: m.ForgotPasswordPage,
  }));

/** Helper: wraps a default-export page component for react-router v7 lazy(). */
function lazyPage(
  imp: () => Promise<{ default: React.ComponentType<unknown> }>
) {
  return async () => {
    const m = await imp();
    return { Component: m.default };
  };
}

const migratedPage = (pageId: string) => <MigratedRoutePage pageId={pageId} />;

export const router = createBrowserRouter([
  // ===== Root =====
  { path: "/", element: <Navigate to="/splash" replace /> },

  // ===== Public routes =====
  { path: "/splash", element: <SplashPage /> },
  { path: "/login", element: <LoginPage /> },
  { path: "/forgot-password", lazy: ForgotPasswordPage },
  { path: "/reset-password", element: <ResetPasswordPage /> },
  { path: "/item/:lookupKey", element: migratedPage("PublicItemScanPage") },

  // ===== Authenticated routes =====
  {
    element: <AuthGuard />,
    children: [
      // ---- Owner Shell ----
      {
        element: <OwnerAppShell />,
        children: [
          { path: "/home", element: migratedPage("HomePage") },
          { path: "/home/activity", element: migratedPage("ActivityPage") },
          { path: "/home/breakdown-more", element: migratedPage("BreakdownListPage") },
          { path: "/stock", lazy: lazyPage(() => import("./pages/stock/StockPage")) },
          { path: "/reports", element: migratedPage("ReportsPage") },
          { path: "/purchase", element: migratedPage("PurchaseHomePage") },
          { path: "/search", element: migratedPage("SearchPage") },
        ],
      },

      // ---- Staff Shell ----
      {
        element: <StaffAppShell />,
        children: [
          { path: "/staff/home", element: migratedPage("StaffHomePage") },
          { path: "/staff/stock", element: migratedPage("StaffStockPage") },
          { path: "/staff/scan", element: migratedPage("StaffScanPage") },
          { path: "/staff/search", element: migratedPage("StaffSearchPage") },
          { path: "/staff/deliveries", element: migratedPage("StaffDeliveriesPage") },
          { path: "/staff/tasks", element: migratedPage("StaffTasksPage") },
        ],
      },

      // ---- Standalone authenticated routes ----
      { path: "/contacts", element: migratedPage("ContactsPage") },
      { path: "/contacts/supplier/new", element: migratedPage("SupplierCreateSimplePage") },
      { path: "/contacts/category", element: migratedPage("CategoryItemsPage") },

      { path: "/catalog", lazy: lazyPage(() => import("./pages/catalog/CatalogPage")) },
      { path: "/catalog/missing-codes", lazy: lazyPage(() => import("./pages/catalog/MissingCodesPage")) },
      { path: "/catalog/quick-add", lazy: lazyPage(() => import("./pages/catalog/QuickAddPage")) },
      { path: "/catalog/quick-add-from-scan", lazy: lazyPage(() => import("./pages/catalog/QuickAddFromScanPage")) },
      { path: "/catalog/setup-reorder-levels", lazy: lazyPage(() => import("./pages/catalog/SetupReorderLevelsPage")) },
      { path: "/catalog/taxonomy", lazy: lazyPage(() => import("./pages/catalog/TaxonomyHubPage")) },
      { path: "/catalog/new-category", lazy: lazyPage(() => import("./pages/catalog/AddCategoryPage")) },
      { path: "/catalog/category/:categoryId/new-subcategory", lazy: lazyPage(() => import("./pages/catalog/AddSubcategoryPage")) },
      { path: "/catalog/category/:categoryId/type/:typeId/add-item", lazy: lazyPage(() => import("./pages/catalog/AddItemPage")) },
      { path: "/catalog/item/:itemId", lazy: lazyPage(() => import("./pages/catalog/ItemDetailPage")) },
      { path: "/catalog/item/:itemId/edit", lazy: lazyPage(() => import("./pages/catalog/ItemEditPage")) },
      { path: "/catalog/item/:itemId/timeline", lazy: lazyPage(() => import("./pages/catalog/ItemTimelinePage")) },
      { path: "/catalog/item/:itemId/purchase-history", lazy: lazyPage(() => import("./pages/catalog/ItemHistoryPage")) },
      { path: "/catalog/item/:itemId/ledger", lazy: lazyPage(() => import("./pages/catalog/TradeLedgerPage")) },
      { path: "/catalog/category/:categoryId", lazy: lazyPage(() => import("./pages/catalog/CategoryDetailPage")) },
      { path: "/catalog/category/:categoryId/type/:typeId", lazy: lazyPage(() => import("./pages/catalog/TypeItemsPage")) },
      { path: "/catalog/duplicates", lazy: lazyPage(() => import("./pages/catalog/DuplicatesPage")) },

      { path: "/barcode/scan", element: migratedPage("BarcodeScanPage") },
      { path: "/barcode/scan-history", element: migratedPage("ScanHistoryPage") },
      { path: "/barcode/audit-session", element: migratedPage("AuditSessionPage") },
      { path: "/barcode/audit-summary", element: migratedPage("AuditSummaryPage") },
      { path: "/barcode/print/:itemId", element: migratedPage("BarcodePrintPage") },
      { path: "/barcode/bulk-print", element: migratedPage("BulkBarcodePrintPage") },

      { path: "/stock/missing-barcodes", element: migratedPage("MissingLabelsPage") },
      { path: "/stock/reorder", element: migratedPage("ReorderListPage") },
          { path: "/stock/item/:itemId", lazy: lazyPage(() => import("./pages/stock/StockDetailPage")) },
          { path: "/stock/opening-setup", lazy: lazyPage(() => import("./pages/stock/OpeningStockSetupPage")) },
          { path: "/stock/staff-purchases", element: migratedPage("StaffPurchaseLogsPage") },
      { path: "/stock/low-stock", element: migratedPage("LowStockDashboardPage") },

      { path: "/purchase/new", element: migratedPage("PurchaseNewPage") },
      { path: "/purchase/edit/:purchaseId", element: migratedPage("PurchaseEditPage") },
      { path: "/purchase/detail/:purchaseId", element: migratedPage("PurchaseDetailPage") },

      { path: "/supplier/:supplierId", lazy: lazyPage(() => import("./pages/supplier/SupplierDetailPage")) },
      { path: "/supplier/:supplierId/ledger", lazy: lazyPage(() => import("./pages/supplier/SupplierLedgerPage")) },
      { path: "/supplier/:supplierId/batch-items", element: migratedPage("BatchItemCreatePage") },
      { path: "/suppliers/quick-create", element: migratedPage("SupplierQuickCreatePage") },

      { path: "/broker/:brokerId", element: migratedPage("BrokerDetailPage") },
      { path: "/broker/:brokerId/ledger", element: migratedPage("BrokerHistoryPage") },
      { path: "/brokers/quick-create", element: migratedPage("BrokerWizardPage") },

      { path: "/reports/item/:catalogItemId", element: migratedPage("ItemReportPage") },
      { path: "/reports/purchase/:purchaseId", element: migratedPage("PurchaseReportPage") },
      { path: "/reports/item-detail", element: migratedPage("ItemReportFallbackPage") },

      { path: "/item-analytics/:itemKey", element: migratedPage("ItemAnalyticsRedirectPage") },

      { path: "/settings", lazy: lazyPage(() => import("./pages/settings/SettingsPage")) },
      { path: "/settings/business", lazy: lazyPage(() => import("./pages/settings/BusinessProfilePage")) },
      { path: "/settings/backup", lazy: lazyPage(() => import("./pages/settings/BackupPage")) },
      { path: "/settings/help", lazy: lazyPage(() => import("./pages/settings/HelpGuidePage")) },
      { path: "/settings/users", lazy: lazyPage(() => import("./pages/settings/UserManagementPage")) },
      { path: "/settings/users/:userId", lazy: lazyPage(() => import("./pages/settings/UserProfilePage")) },
      { path: "/settings/profile", lazy: lazyPage(() => import("./pages/settings/UserProfilePage")) },

      { path: "/staff/receive", element: migratedPage("StaffReceivePage") },
      { path: "/staff/receive/:purchaseId", element: migratedPage("StaffReceiveShipmentPage") },
      { path: "/staff/low-stock", element: migratedPage("StaffLowStockPage") },
      { path: "/staff/items", element: migratedPage("StaffItemsPage") },
      { path: "/staff/settings", element: migratedPage("StaffSettingsPage") },
      { path: "/staff/purchase-history", element: migratedPage("StaffPurchaseHistoryPage") },
      { path: "/staff/activity", element: migratedPage("StaffActivityPage") },
      { path: "/staff/purchase-history/:purchaseId", element: migratedPage("StaffPurchaseOrderDetailPage") },

      { path: "/notifications", element: migratedPage("NotificationsPage") },

      { path: "/operations/usage", element: migratedPage("DailyUsagePage") },
      { path: "/operations/checklist", element: migratedPage("StaffChecklistPage") },
      { path: "/operations/owner-tasks", element: migratedPage("OwnerTasksPage") },
    ],
  },

  // ===== Legacy redirects =====
  { path: "/dashboard", element: <Navigate to="/home" replace /> },
  { path: "/history", element: <Navigate to="/purchase" replace /> },
  { path: "/entries", element: <Navigate to="/purchase" replace /> },
  { path: "/analytics", element: <Navigate to="/reports" replace /> },
  { path: "/get-started", element: <Navigate to="/login" replace /> },
  { path: "/scan/:token", element: <Navigate to="/item/:token" replace /> },
  { path: "/stock/movement", element: <Navigate to="/stock?tab=movement" replace /> },
  { path: "/stock/changes", element: <Navigate to="/stock?tab=changes" replace /> },
  { path: "/stock/reorder-suggestions", element: <Navigate to="/stock/reorder" replace /> },
  { path: "/stock/today-feed", element: <Navigate to="/stock?tab=today" replace /> },
  { path: "/stock/intelligence/:itemId", element: <Navigate to="/catalog/item/:itemId?source=intelligence" replace /> },
  { path: "/stock/:itemId/history", element: <Navigate to="/catalog/item/:itemId?tab=history" replace /> },
  { path: "/stock/dead", element: <Navigate to="/reports?tab=stock&section=dead" replace /> },
  { path: "/stock/fast-moving", element: <Navigate to="/reports?tab=stock&section=fast" replace /> },
  { path: "/stock/slow-moving", element: <Navigate to="/reports?tab=stock&section=slow" replace /> },
  { path: "/catalog/item/create", element: <Navigate to="/catalog/quick-add" replace /> },
  { path: "/staff/stock/changes", element: <Navigate to="/staff/stock?tab=changes" replace /> },
  { path: "/purchase/scan", element: <Navigate to="/purchase/new" replace /> },
  { path: "/purchase/scan-draft", element: <Navigate to="/purchase/new" replace /> },
]);
