// ---- Session / Auth ----
export interface Session {
  id: string;
  email: string;
  name: string;
  primaryBusiness: {
    id: string;
    name: string;
    role: string;
    currency: string;
  };
}

export interface LoginRequest {
  email: string;
  password: string;
}

export interface LoginResponse {
  accessToken: string;
  refreshToken: string;
  session: Session;
}

export interface BusinessUser {
  id: string;
  name: string;
  role: string;
}

// ---- Purchase Draft (mirrors Flutter PurchaseDraft + PurchaseLineDraft) ----
export interface PurchaseDraftLine {
  catalogItemId: string;
  itemName: string;
  qty: number;
  unit: string;
  landingCost: number;
  kgPerUnit: number | null;
  landingCostPerKg: number | null;
  discountPercent: number | null;
  taxPercent: number | null;
  lineDiscountPercent: number | null;
  freightType: string | null;
  freightValue: number | null;
  deliveredRate: number | null;
  billtyRate: number | null;
  boxMode: string | null;
  itemsPerBox: number | null;
  weightPerItem: number | null;
  kgPerBox: number | null;
  weightPerTin: number | null;
}

export interface PurchaseDraft {
  supplierId: string | null;
  supplierName: string | null;
  brokerId: string | null;
  brokerName: string | null;
  purchaseDate: string;
  invoiceText: string;
  headerDiscountPercent: number | null;
  commissionMode: string;
  commissionPercent: number | null;
  commissionMoney: number | null;
  freightAmount: number | null;
  freightType: string;
  billtyRate: number | null;
  deliveredRate: number | null;
  lines: PurchaseDraftLine[];
}

// ---- Calc engine types (mirrors Flutter TradeCalcLine / TradeCalcRequest / TradeCalcTotals) ----
export interface CalcLine {
  qty: number;
  landingCost: number;
  kgPerUnit: number | null;
  landingCostPerKg: number | null;
  discountPercent: number | null;
  taxPercent: number | null;
  freightType: string | null;
  freightValue: number | null;
  deliveredRate: number | null;
  billtyRate: number | null;
}

export interface CommissionLine {
  itemName: string;
  unit: string;
  qty: number;
  kgPerUnit: number | null;
  catalogDefaultUnit: string | null;
  catalogDefaultKgPerBag: number | null;
  boxMode: string | null;
  itemsPerBox: number | null;
  weightPerItem: number | null;
  kgPerBox: number | null;
  weightPerTin: number | null;
}

export interface CalcRequest {
  lines: CalcLine[];
  headerDiscountPercent: number | null;
  commissionPercent: number | null;
  commissionMode: string;
  commissionMoney: number | null;
  commissionBasisLines: CommissionLine[];
  freightAmount: number | null;
  freightType: string | null;
  billtyRate: number | null;
  deliveredRate: number | null;
  lineTaxMode: "exclusive" | "inclusive" | "none";
}

export interface CalcTotals {
  qtySum: number;
  amountSum: number;
}

export interface PurchaseStrictBreakdown {
  subtotalGross: number;
  taxTotal: number;
  discountTotal: number;
  freight: number;
  commission: number;
  grand: number;
}

// ---- Trade purchase list ----
export interface TradePurchaseRow {
  id: string;
  supplier_name?: string;
  supplier_id?: string;
  total_amount?: number;
  total_qty?: number;
  status?: string;
  purchase_date?: string;
  due_date?: string;
  [key: string]: unknown;
}

export interface TradePurchasesPage {
  rows: TradePurchaseRow[];
  hasMore: boolean;
}

// ---- Contacts ----
export interface SupplierRow {
  id: string;
  name: string;
  gst?: string;
  phone?: string;
}

export interface SupplierDetail {
  id: string;
  name: string;
  phone: string | null;
  location: string | null;
  broker_id: string | null;
  broker_ids: string[];
  gst_number: string | null;
  address: string | null;
  notes: string | null;
  default_payment_days: number | null;
  default_discount: number | null;
  default_delivered_rate: number | null;
  default_billty_rate: number | null;
  freight_type: string | null;
  ai_memory_enabled: boolean;
  preferences_json: string | null;
  last_purchase_date: string | null;
}

export interface SupplierMetrics {
  deals: number;
  total_qty: number;
  avg_landing: number;
  total_profit: number;
  purchase_amount: number;
  profit_margin_pct: number;
}

export interface SupplierLedgerRow {
  purchase_id: string;
  human_id: string;
  purchase_date: string;
  invoice_number: string | null;
  status: string;
  total_amount: number;
  paid_amount: number;
  balance: number;
  due_date: string | null;
}

export interface SupplierLedger {
  supplier_id: string;
  supplier_name: string;
  phone: string | null;
  rows: SupplierLedgerRow[];
  total_amount: number;
  total_paid: number;
  total_balance: number;
}

export interface BrokerRow {
  id: string;
  name: string;
  commission?: number;
}

// ---- Stock Opening Setup ----
export interface OpeningStockSetupItem {
  id: string;
  name: string;
  item_code: string | null;
  barcode: string | null;
  category_name: string | null;
  subcategory_name: string | null;
  unit: string | null;
  current_stock: number;
  stock_status: string;
  setup_status: "pending" | "completed";
  barcode_state: "ok" | "missing";
  opening_stock_qty: number | null;
  opening_stock_locked: boolean;
  opening_stock_set_at: string | null;
  opening_stock_set_by: string | null;
  stock_version: number;
  [key: string]: unknown;
}

export interface OpeningStockSetupSummary {
  pending_count: number;
  completed_count: number;
  total_count: number;
  last_updated_at: string | null;
  last_updated_by: string | null;
}

export interface OpeningStockSetupResponse {
  summary: OpeningStockSetupSummary;
  items: OpeningStockSetupItem[];
  total: number;
  page: number;
  per_page: number;
}

// ---- Business Profile ----
export interface BusinessBrief {
  id: string;
  name: string;
  role: string;
  permissions: Record<string, boolean>;
  branding_title: string | null;
  branding_logo_url: string | null;
  gst_number: string | null;
  address: string | null;
  phone: string | null;
  contact_email: string | null;
}

export interface BusinessBrandingPatch {
  name?: string | null;
  branding_title?: string | null;
  branding_logo_url?: string | null;
  gst_number?: string | null;
  address?: string | null;
  phone?: string | null;
  contact_email?: string | null;
}

// ---- User Management ----
export interface UserListOut {
  id: string;
  name: string | null;
  phone: string | null;
  email: string;
  username: string | null;
  role: string;
  is_active: boolean;
  is_blocked: boolean;
  last_login_at: string | null;
  last_active_at: string | null;
  today_stats: {
    purchases_count: number;
    stock_updates_count: number;
  } | null;
  warehouse_name: string | null;
  activity_count_7d: number;
  notes: string | null;
  created_at: string | null;
}

export interface UserProfileOut extends UserListOut {
  login_email: string | null;
  purchases_7d: number;
  stock_updates_7d: number;
  stats: {
    total_purchases: number;
    total_stock_updates: number;
    total_activity_count: number;
  } | null;
}

export interface UserCreateIn {
  full_name: string;
  email?: string | null;
  phone: string;
  role: "admin" | "manager" | "staff";
  password?: string | null;
  notes?: string | null;
  is_active?: boolean;
}

export interface UserCreateOut {
  user: UserListOut;
  generated_password: string | null;
  login_email: string | null;
}

export interface UserPatchIn {
  full_name?: string | null;
  email?: string | null;
  phone?: string | null;
  role?: string | null;
  is_active?: boolean | null;
  is_blocked?: boolean | null;
  notes?: string | null;
}

export interface UserBulkIn {
  user_ids: string[];
  action: "activate" | "deactivate" | "block" | "unblock" | "delete" | "set_role";
  role?: string | null;
}

export interface UserBulkOut {
  updated: number;
  failed: string[];
}

export interface ResetPasswordOut {
  new_password: string;
  login_email: string | null;
}

// ---- User Profile (self) ----
export interface UserProfile {
  id: string;
  email: string;
  username: string;
  name: string | null;
  is_super_admin: boolean;
}
