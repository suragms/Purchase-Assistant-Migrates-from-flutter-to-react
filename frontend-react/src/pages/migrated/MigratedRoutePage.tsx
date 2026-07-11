import { Link, useLocation, useParams } from "react-router-dom";
import {
  LuActivity,
  LuArchive,
  LuBadgeCheck,
  LuBell,
  LuBoxes,
  LuBuilding2,
  LuCalendarDays,
  LuChartBar,
  LuClipboardCheck,
  LuClipboardList,
  LuContact,
  LuDatabase,
  LuFileText,
  LuLayoutDashboard,
  LuPackage,
  LuPackageCheck,
  LuPackagePlus,
  LuScanLine,
  LuSearch,
  LuSettings,
  LuShieldCheck,
  LuShoppingCart,
  LuUsers,
} from "react-icons/lu";
import type { IconType } from "react-icons";
import { OperationsConsole } from "./OperationsConsole";

type Action = {
  label: string;
  to: string;
};

type SectionConfig = {
  title: string;
  eyebrow: string;
  icon: IconType;
  description: string;
  metrics: string[];
  workflows: string[];
  tables: string[];
  actions: Action[];
};

const ownerActions: Action[] = [
  { label: "New purchase", to: "/purchase/new" },
  { label: "Scan barcode", to: "/barcode/scan" },
  { label: "Catalog", to: "/catalog" },
  { label: "Reports", to: "/reports" },
];

const staffActions: Action[] = [
  { label: "Receive shipment", to: "/staff/receive" },
  { label: "Scan stock", to: "/staff/scan" },
  { label: "Purchase history", to: "/staff/purchase-history" },
  { label: "Tasks", to: "/staff/tasks" },
];

const configs: Record<string, SectionConfig> = {
  home: {
    title: "Owner Home",
    eyebrow: "Dashboard",
    icon: LuLayoutDashboard,
    description:
      "Owner control center for purchases, warehouse health, low-stock attention, pending deliveries, and recent activity.",
    metrics: ["Today spend", "Pending deliveries", "Low and out stock", "Recent stock changes"],
    workflows: ["Review live alerts", "Jump to purchase entry", "Open low-stock operations", "Track warehouse activity"],
    tables: ["trade_purchases", "catalog_items", "stock_movements", "notifications"],
    actions: ownerActions,
  },
  "home-activity": {
    title: "Warehouse Activity",
    eyebrow: "Activity",
    icon: LuActivity,
    description:
      "Chronological activity feed for purchase creation, delivery verification, staff quantity updates, and stock corrections.",
    metrics: ["Activity count", "Delivery events", "Staff edits", "Stock corrections"],
    workflows: ["Filter activity by period", "Open linked purchase", "Open linked stock item", "Review staff actions"],
    tables: ["staff_activity_log", "stock_movements", "purchase_lifecycle_events", "admin_audit_logs"],
    actions: [{ label: "Back home", to: "/home" }, { label: "Notifications", to: "/notifications" }],
  },
  "home-breakdown": {
    title: "Spend Breakdown",
    eyebrow: "Analytics",
    icon: LuChartBar,
    description:
      "Expanded category and item spending breakdown migrated from the Flutter owner dashboard drill-down.",
    metrics: ["Category totals", "Item totals", "Period comparison", "Supplier mix"],
    workflows: ["Change period", "Open item report", "Open purchase report", "Export from reports"],
    tables: ["trade_purchases", "trade_purchase_lines", "item_categories", "catalog_items"],
    actions: [{ label: "Reports", to: "/reports" }, { label: "Purchases", to: "/purchase" }],
  },
  purchase: {
    title: "Purchase History",
    eyebrow: "Purchases",
    icon: LuShoppingCart,
    description:
      "Purchase list, delivery lifecycle, invoice totals, supplier and broker links, and edit/detail navigation.",
    metrics: ["Purchase count", "Pending amount", "Delivered orders", "Draft resume"],
    workflows: ["Create purchase", "Edit purchase", "Receive delivery", "Open supplier ledger"],
    tables: ["trade_purchases", "trade_purchase_lines", "purchase_lifecycle_events", "purchase_damage_reports"],
    actions: [
      { label: "New purchase", to: "/purchase/new" },
      { label: "Receive", to: "/staff/receive" },
      { label: "Reports", to: "/reports" },
    ],
  },
  "purchase-new": {
    title: "New Purchase",
    eyebrow: "Entry",
    icon: LuPackagePlus,
    description:
      "Three-step purchase workflow for party selection, item entry, terms, taxes, commissions, freight, and review.",
    metrics: ["Draft lines", "Subtotal", "Tax", "Grand total"],
    workflows: ["Select supplier or broker", "Add catalog lines", "Calculate landed rates", "Save and dispatch"],
    tables: ["trade_purchase_drafts", "trade_purchases", "trade_purchase_lines", "supplier_item_defaults"],
    actions: [{ label: "Purchase history", to: "/purchase" }, { label: "Quick supplier", to: "/suppliers/quick-create" }],
  },
  "purchase-detail": {
    title: "Purchase Detail",
    eyebrow: "Purchase",
    icon: LuFileText,
    description:
      "Purchase detail, line items, delivery timeline, damage reports, stock commit state, and export actions.",
    metrics: ["Line total", "Paid amount", "Delivery status", "Stock committed"],
    workflows: ["Verify delivery", "Edit purchase", "Record damage", "Print invoice"],
    tables: ["trade_purchases", "trade_purchase_lines", "purchase_lifecycle_events", "stock_movements"],
    actions: [{ label: "Purchase history", to: "/purchase" }, { label: "Reports", to: "/reports" }],
  },
  contacts: {
    title: "Contacts",
    eyebrow: "Suppliers and Brokers",
    icon: LuContact,
    description:
      "Supplier and broker directory with trade ledgers, default commercial terms, linked catalog defaults, and quick creation.",
    metrics: ["Suppliers", "Brokers", "Linked parties", "Recent trades"],
    workflows: ["Add supplier", "Add broker", "Open ledger", "Review default rates"],
    tables: ["suppliers", "brokers", "broker_supplier_m2m", "supplier_item_defaults"],
    actions: [
      { label: "New supplier", to: "/contacts/supplier/new" },
      { label: "Quick broker", to: "/brokers/quick-create" },
      { label: "Category items", to: "/contacts/category" },
    ],
  },
  supplier: {
    title: "Supplier Workspace",
    eyebrow: "Supplier",
    icon: LuBuilding2,
    description:
      "Supplier profile, ledger, defaults, related purchases, batch item creation, and statement flow.",
    metrics: ["Total purchases", "Outstanding", "Default discount", "Recent items"],
    workflows: ["Open ledger", "Create batch items", "Start purchase", "Review supplier terms"],
    tables: ["suppliers", "trade_purchases", "trade_purchase_lines", "supplier_item_defaults"],
    actions: [{ label: "Contacts", to: "/contacts" }, { label: "Batch items", to: "/supplier/:supplierId/batch-items" }],
  },
  broker: {
    title: "Broker Workspace",
    eyebrow: "Broker",
    icon: LuUsers,
    description:
      "Broker profile, commission defaults, supplier links, purchase history, and broker statement routes.",
    metrics: ["Linked suppliers", "Commission", "Recent purchases", "Ledger total"],
    workflows: ["Review broker ledger", "Update commission terms", "Open linked suppliers", "Create purchase"],
    tables: ["brokers", "broker_supplier_m2m", "trade_purchases", "trade_purchase_lines"],
    actions: [{ label: "Contacts", to: "/contacts" }, { label: "Quick broker", to: "/brokers/quick-create" }],
  },
  reports: {
    title: "Reports",
    eyebrow: "Analytics",
    icon: LuChartBar,
    description:
      "Overview, purchases, items, stock, drill-down reports, saved views, exports, and operational report slices.",
    metrics: ["Gross spend", "Profit", "Stock value", "Saved views"],
    workflows: ["Open item report", "Open purchase report", "Filter period", "Export report"],
    tables: ["report_saved_views", "trade_purchases", "trade_purchase_lines", "stock_movements"],
    actions: [
      { label: "Purchase history", to: "/purchase" },
      { label: "Stock", to: "/stock" },
      { label: "Catalog", to: "/catalog" },
    ],
  },
  search: {
    title: "Unified Search",
    eyebrow: "Search",
    icon: LuSearch,
    description:
      "Search across catalog items, suppliers, brokers, purchases, item codes, and barcode/public-token lookups.",
    metrics: ["Items", "Suppliers", "Brokers", "Purchases"],
    workflows: ["Search by barcode", "Open item detail", "Open purchase", "Open party ledger"],
    tables: ["catalog_items", "suppliers", "brokers", "trade_purchases"],
    actions: [{ label: "Scan", to: "/barcode/scan" }, { label: "Catalog", to: "/catalog" }],
  },
  barcode: {
    title: "Barcode Center",
    eyebrow: "Barcode",
    icon: LuScanLine,
    description:
      "Barcode scanning, public item lookup, audit sessions, scan history, single-label print, and bulk print workflows.",
    metrics: ["Scans", "Audit variance", "Printable labels", "Missing labels"],
    workflows: ["Scan item", "Create from scan", "Run stock audit", "Print labels"],
    tables: ["catalog_items", "stock_audits", "stock_audit_items", "stock_physical_counts"],
    actions: [
      { label: "Scan", to: "/barcode/scan" },
      { label: "Audit session", to: "/barcode/audit-session" },
      { label: "Bulk print", to: "/barcode/bulk-print" },
      { label: "Missing labels", to: "/stock/missing-barcodes" },
    ],
  },
  notifications: {
    title: "Notifications",
    eyebrow: "Alerts",
    icon: LuBell,
    description:
      "Role-aware notification center for low stock, delivery idle alerts, physical count reminders, missing labels, and staff requests.",
    metrics: ["Unread", "Critical", "Delivery alerts", "Stock alerts"],
    workflows: ["Acknowledge alert", "Open deep link", "Filter priority", "Review notification payload"],
    tables: ["notifications", "staff_activity_log", "stock_dispute_cases", "reorder_list"],
    actions: [{ label: "Home", to: "/home" }, { label: "Settings", to: "/settings" }],
  },
  settings: {
    title: "Settings",
    eyebrow: "Admin",
    icon: LuSettings,
    description:
      "Business profile, backups, user management, permissions, help guide, notification preferences, and account settings.",
    metrics: ["Business profile", "Users", "Backups", "Permissions"],
    workflows: ["Update business profile", "Manage users", "Open backup tools", "Read help guide"],
    tables: ["businesses", "users", "memberships", "admin_audit_logs"],
    actions: [
      { label: "Business profile", to: "/settings/business" },
      { label: "Users", to: "/settings/users" },
      { label: "Backup", to: "/settings/backup" },
      { label: "Help", to: "/settings/help" },
    ],
  },
  operations: {
    title: "Operations",
    eyebrow: "Daily Work",
    icon: LuClipboardCheck,
    description:
      "Daily usage logging, staff checklist completion, owner task review, recurring reminders, and operational audit trails.",
    metrics: ["Usage entries", "Checklist completion", "Owner tasks", "Due reminders"],
    workflows: ["Submit usage", "Complete checklist", "Review owner tasks", "Track operational logs"],
    tables: ["daily_usage_logs", "staff_checklist_templates", "staff_checklist_completions", "staff_activity_log"],
    actions: [
      { label: "Daily usage", to: "/operations/usage" },
      { label: "Checklist", to: "/operations/checklist" },
      { label: "Owner tasks", to: "/operations/owner-tasks" },
    ],
  },
  stock: {
    title: "Stock Operations",
    eyebrow: "Inventory",
    icon: LuBoxes,
    description:
      "Stock list, item stock detail, opening setup, reorder levels, low-stock dashboard, physical counts, and staff purchase logs.",
    metrics: ["System stock", "Physical stock", "Difference", "Pending delivery"],
    workflows: ["Adjust stock", "Set opening stock", "Review low stock", "Print missing labels"],
    tables: ["catalog_items", "stock_movements", "stock_physical_counts", "reorder_list"],
    actions: [
      { label: "Stock", to: "/stock" },
      { label: "Low stock", to: "/stock/low-stock" },
      { label: "Opening setup", to: "/stock/opening-setup" },
      { label: "Reorder", to: "/stock/reorder" },
    ],
  },
  staff: {
    title: "Staff Workspace",
    eyebrow: "Staff",
    icon: LuShieldCheck,
    description:
      "Staff dashboard for receiving deliveries, scanning items, checking stock, purchase history, tasks, activity, and low-stock requests.",
    metrics: ["Pending deliveries", "Tasks due", "Low stock", "Recent activity"],
    workflows: ["Receive shipment", "Scan item", "Check stock", "Inform owner"],
    tables: ["trade_purchases", "stock_physical_counts", "staff_checklist_completions", "staff_activity_log"],
    actions: staffActions,
  },
  catalog: {
    title: "Catalog",
    eyebrow: "Items",
    icon: LuPackage,
    description:
      "Migrated catalog hierarchy, item details, item edit, taxonomy, duplicates, missing codes, quick add, default suppliers, and item timeline.",
    metrics: ["Categories", "Types", "Items", "Missing codes"],
    workflows: ["Add item", "Edit item", "Assign barcode", "Review duplicates"],
    tables: ["item_categories", "category_types", "catalog_items", "catalog_variants"],
    actions: [
      { label: "Catalog", to: "/catalog" },
      { label: "Quick add", to: "/catalog/quick-add" },
      { label: "Taxonomy", to: "/catalog/taxonomy" },
      { label: "Duplicates", to: "/catalog/duplicates" },
    ],
  },
};

const pageToSection: Record<string, keyof typeof configs> = {
  HomePage: "home",
  ActivityPage: "home-activity",
  BreakdownListPage: "home-breakdown",
  PurchaseHomePage: "purchase",
  PurchaseNewPage: "purchase-new",
  PurchaseEditPage: "purchase-detail",
  PurchaseDetailPage: "purchase-detail",
  ContactsPage: "contacts",
  CategoryItemsPage: "contacts",
  SupplierCreatePage: "contacts",
  SupplierCreateSimplePage: "contacts",
  SupplierQuickCreatePage: "contacts",
  SupplierDetailPage: "supplier",
  SupplierLedgerPage: "supplier",
  BatchItemCreatePage: "supplier",
  BrokerDetailPage: "broker",
  BrokerHistoryPage: "broker",
  BrokerWizardPage: "broker",
  ReportsPage: "reports",
  ItemReportPage: "reports",
  ItemReportFallbackPage: "reports",
  PurchaseReportPage: "reports",
  SearchPage: "search",
  BarcodeScanPage: "barcode",
  ScanHistoryPage: "barcode",
  AuditSessionPage: "barcode",
  AuditSummaryPage: "barcode",
  BarcodePrintPage: "barcode",
  BulkBarcodePrintPage: "barcode",
  PublicItemScanPage: "barcode",
  NotificationsPage: "notifications",
  SettingsPage: "settings",
  BusinessProfilePage: "settings",
  BackupPage: "settings",
  HelpGuidePage: "settings",
  UserManagementPage: "settings",
  UserProfilePage: "settings",
  DailyUsagePage: "operations",
  StaffChecklistPage: "operations",
  OwnerTasksPage: "operations",
  LowStockDashboardPage: "stock",
  MissingLabelsPage: "stock",
  OpeningStockSetupPage: "stock",
  ReorderListPage: "stock",
  StaffPurchaseLogsPage: "stock",
  StaffHomePage: "staff",
  StaffStockPage: "staff",
  StaffScanPage: "staff",
  StaffSearchPage: "staff",
  StaffDeliveriesPage: "staff",
  StaffTasksPage: "staff",
  StaffReceivePage: "staff",
  StaffReceiveShipmentPage: "staff",
  StaffLowStockPage: "staff",
  StaffItemsPage: "staff",
  StaffSettingsPage: "staff",
  StaffPurchaseHistoryPage: "staff",
  StaffPurchaseOrderDetailPage: "staff",
  StaffActivityPage: "staff",
  ItemAnalyticsRedirectPage: "reports",
};

function resolveActionPath(to: string, params: Record<string, string | undefined>) {
  return Object.entries(params).reduce(
    (path, [key, value]) => path.replace(`:${key}`, value || ""),
    to
  );
}

export function MigratedRoutePage({ pageId }: { pageId: string }) {
  const location = useLocation();
  const params = useParams();
  const config = configs[pageToSection[pageId] || "catalog"];
  const Icon = config.icon;
  const idEntries = Object.entries(params).filter(([, value]) => Boolean(value));

  return (
    <main className="mx-auto flex w-full max-w-6xl flex-col gap-4 px-4 py-4 sm:px-6 lg:px-8">
      <section className="rounded-card border border-brand-border bg-white p-4 shadow-[0_8px_22px_rgba(14,79,70,0.06)] sm:p-5">
        <div className="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
          <div className="flex min-w-0 gap-3">
            <div className="flex h-12 w-12 shrink-0 items-center justify-center rounded-xl bg-brand-primary/10 text-brand-primary">
              <Icon size={24} />
            </div>
            <div className="min-w-0">
              <p className="text-xs font-bold uppercase text-brand-accent">{config.eyebrow}</p>
              <h1 className="mt-1 text-2xl font-extrabold text-text-primary sm:text-3xl">{config.title}</h1>
              <p className="mt-2 max-w-3xl text-sm leading-6 text-text-body">{config.description}</p>
            </div>
          </div>
          <div className="rounded-xl border border-brand-border bg-brand-background px-3 py-2 text-xs font-semibold text-text-muted">
            {pageId}
          </div>
        </div>
      </section>

      <OperationsConsole pageId={pageId} />

      <section className="grid gap-3 md:grid-cols-4">
        {config.metrics.map((metric) => (
          <div key={metric} className="rounded-card border border-brand-border bg-white p-4">
            <p className="text-xs font-semibold uppercase text-text-muted">Migrated KPI</p>
            <p className="mt-2 text-sm font-bold text-text-primary">{metric}</p>
          </div>
        ))}
      </section>

      <section className="grid gap-4 lg:grid-cols-[1.3fr_0.9fr]">
        <div className="rounded-card border border-brand-border bg-white p-4">
          <div className="flex items-center gap-2">
            <LuClipboardList size={18} className="text-brand-primary" />
            <h2 className="text-base font-bold text-text-primary">Workflow Coverage</h2>
          </div>
          <div className="mt-4 grid gap-2 sm:grid-cols-2">
            {config.workflows.map((workflow) => (
              <div key={workflow} className="flex items-start gap-2 rounded-xl bg-brand-background p-3">
                <LuBadgeCheck size={17} className="mt-0.5 shrink-0 text-profit" />
                <span className="text-sm font-medium text-text-body">{workflow}</span>
              </div>
            ))}
          </div>
        </div>

        <div className="rounded-card border border-brand-border bg-white p-4">
          <div className="flex items-center gap-2">
            <LuDatabase size={18} className="text-brand-primary" />
            <h2 className="text-base font-bold text-text-primary">Database Surface</h2>
          </div>
          <div className="mt-4 flex flex-wrap gap-2">
            {config.tables.map((table) => (
              <span key={table} className="rounded-full border border-brand-border px-3 py-1.5 text-xs font-semibold text-text-body">
                {table}
              </span>
            ))}
          </div>
        </div>
      </section>

      <section className="rounded-card border border-brand-border bg-white p-4">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h2 className="text-base font-bold text-text-primary">Menu Actions</h2>
            <p className="text-sm text-text-muted">Route links are wired into the React shell for this migrated section.</p>
          </div>
          <div className="flex flex-wrap gap-2">
            {config.actions.map((action) => (
              <Link
                key={`${action.label}-${action.to}`}
                to={resolveActionPath(action.to, params)}
                className="inline-flex h-10 items-center justify-center rounded-xl bg-brand-primary px-3 text-sm font-bold text-white hover:bg-brand-hover"
              >
                {action.label}
              </Link>
            ))}
          </div>
        </div>
      </section>

      <section className="rounded-card border border-brand-border bg-white p-4">
        <div className="grid gap-3 md:grid-cols-3">
          <div className="flex items-center gap-2">
            <LuArchive size={18} className="text-brand-primary" />
            <span className="text-sm font-semibold text-text-body">Current path: {location.pathname}</span>
          </div>
          <div className="flex items-center gap-2">
            <LuCalendarDays size={18} className="text-brand-primary" />
            <span className="text-sm font-semibold text-text-body">Flutter parity route retained</span>
          </div>
          <div className="flex items-center gap-2">
            <LuPackageCheck size={18} className="text-brand-primary" />
            <span className="text-sm font-semibold text-text-body">
              {idEntries.length ? idEntries.map(([key, value]) => `${key}: ${value}`).join(" · ") : "List view"}
            </span>
          </div>
        </div>
      </section>
    </main>
  );
}
