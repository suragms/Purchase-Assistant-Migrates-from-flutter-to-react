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

export interface BrokerRow {
  id: string;
  name: string;
  commission?: number;
}
