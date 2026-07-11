import { api } from "./client";

export interface StockListItem {
  id: string;
  name: string;
  itemCode: string | null;
  barcode: string | null;
  categoryName: string | null;
  typeName: string | null;
  defaultUnit: string | null;
  currentStock: number;
  reorderLevel: number | null;
  stockUnit: string | null;
  displayUnit: string | null;
  packageType: string | null;
  validationStatus: string | null;
  lastPurchasePrice: number | null;
  defaultLandingCost: number | null;
  defaultSellingCost: number | null;
  lastSupplierId: string | null;
  lastSupplierName: string | null;
  lastPurchaseDate: string | null;
  daysSinceLastPurchase: number | null;
  status: string;
  pendingOrderQty: number | null;
  hasPendingOrder: boolean;
  periodPurchased: number | null;
  periodUsage: number | null;
  physicalCountVariance: number | null;
  needsVerification: boolean;
  lastMovementAt: string | null;
  stockVersion: number;
  rackLocation: string | null;
  lastStockUpdatedBy: string | null;
}

export interface StockListResponse {
  items: StockListItem[];
  totalCount: number;
}

export interface StockListParams {
  categoryId?: string;
  typeId?: string;
  lowStock?: boolean;
  q?: string;
  page?: number;
  perPage?: number;
}

export interface StockDetailResponse {
  id: string;
  name: string;
  itemCode: string | null;
  barcode: string | null;
  categoryName: string | null;
  typeName: string | null;
  defaultUnit: string | null;
  stockUnit: string | null;
  displayUnit: string | null;
  packageType: string | null;
  hsnCode: string | null;
  currentStock: number;
  reorderLevel: number | null;
  openingStock: number | null;
  openingStockLocked: boolean;
  defaultLandingCost: number | null;
  defaultSellingCost: number | null;
  lastPurchasePrice: number | null;
  lastSellingRate: number | null;
  lastSupplierId: string | null;
  lastSupplierName: string | null;
  lastBrokerId: string | null;
  lastBrokerName: string | null;
  lastPurchaseDate: string | null;
  lastStockUpdatedAt: string | null;
  stockVersion: number;
  validationStatus: string | null;
  rackLocation: string | null;
  publicToken: string | null;
  defaultSupplierIds: string[];
  defaultBrokerIds: string[];
}

export interface PatchStockPayload {
  newQty: number;
  adjustmentType: string;
  reason?: string;
  lastSeenStockVersion?: number;
  idempotencyKey?: string;
}

export interface PhysicalCountPayload {
  countedQty: number;
  notes?: string;
  idempotencyKey?: string;
}

export async function listStock(
  businessId: string,
  params: StockListParams = {}
): Promise<StockListResponse> {
  const res = await api.get(`/businesses/${businessId}/stock/list`, { params });
  return res.data;
}

export async function getStockDetail(
  businessId: string,
  itemId: string
): Promise<StockDetailResponse> {
  const res = await api.get(`/businesses/${businessId}/stock/${itemId}`);
  return res.data;
}

export async function patchStockItem(
  businessId: string,
  itemId: string,
  payload: PatchStockPayload
): Promise<StockDetailResponse> {
  const res = await api.patch(`/businesses/${businessId}/stock/${itemId}`, payload);
  return res.data;
}

export async function recordPhysicalCount(
  businessId: string,
  itemId: string,
  payload: PhysicalCountPayload
): Promise<{ id: string; itemId: string; systemQty: number; countedQty: number }> {
  const res = await api.post(
    `/businesses/${businessId}/stock/${itemId}/physical-count`,
    { ...payload, itemId }
  );
  return res.data;
}
