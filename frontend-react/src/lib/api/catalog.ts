import { api } from "./client";

// ─── Categories ─────────────────────────────────────────────
export interface ItemCategory {
  id: string;
  name: string;
}

export async function listCategories(businessId: string): Promise<ItemCategory[]> {
  const res = await api.get(`/businesses/${businessId}/item-categories`);
  return res.data;
}

export async function createCategory(businessId: string, name: string): Promise<ItemCategory> {
  const res = await api.post(`/businesses/${businessId}/item-categories`, { name });
  return res.data;
}

export async function updateCategory(businessId: string, categoryId: string, name: string): Promise<ItemCategory> {
  const res = await api.patch(`/businesses/${businessId}/item-categories/${categoryId}`, { name });
  return res.data;
}

export async function deleteCategory(businessId: string, categoryId: string): Promise<void> {
  await api.delete(`/businesses/${businessId}/item-categories/${categoryId}`);
}

export interface CategoryTradeSummary {
  itemCount: number;
  totalLineAmount: number;
  totalQtyBags: number;
  totalWeightKg: number;
  items: CategoryTradeItemRow[];
}

export interface CategoryTradeItemRow {
  catalogItemId: string;
  name: string;
  periodLineTotal: number;
  periodQtyBags: number;
  periodWeightKg: number;
  lastPurchasePrice: number | null;
  lastSellingRate: number | null;
  lastSupplierName: string | null;
  lastBrokerName: string | null;
  lastTradeHumanId: string | null;
}

export async function getCategoryTradeSummary(businessId: string, categoryId: string): Promise<CategoryTradeSummary> {
  const res = await api.get(`/businesses/${businessId}/item-categories/${categoryId}/trade-summary`);
  return res.data;
}

// ─── Category Types ─────────────────────────────────────────
export interface CategoryType {
  id: string;
  categoryId: string;
  name: string;
}

export async function listCategoryTypes(businessId: string, categoryId: string): Promise<CategoryType[]> {
  const res = await api.get(`/businesses/${businessId}/item-categories/${categoryId}/category-types`);
  return res.data;
}

export async function createCategoryType(businessId: string, categoryId: string, name: string): Promise<CategoryType> {
  const res = await api.post(`/businesses/${businessId}/item-categories/${categoryId}/category-types`, { name });
  return res.data;
}

export async function updateCategoryType(businessId: string, categoryId: string, typeId: string, name: string): Promise<CategoryType> {
  const res = await api.patch(`/businesses/${businessId}/item-categories/${categoryId}/category-types/${typeId}`, { name });
  return res.data;
}

export async function deleteCategoryType(businessId: string, categoryId: string, typeId: string): Promise<void> {
  await api.delete(`/businesses/${businessId}/item-categories/${categoryId}/category-types/${typeId}`);
}

export interface CategoryTypeIndex {
  id: string;
  categoryId: string;
  categoryName: string;
  name: string;
}

export async function getCategoryTypesIndex(businessId: string): Promise<CategoryTypeIndex[]> {
  const res = await api.get(`/businesses/${businessId}/category-types-index`);
  return res.data;
}

// ─── Catalog Items ──────────────────────────────────────────
export interface CatalogItem {
  id: string;
  categoryId: string;
  typeId: string | null;
  typeName: string | null;
  name: string;
  defaultUnit: string | null;
  defaultKgPerBag: number | null;
  defaultItemsPerBox: number | null;
  defaultWeightPerTin: number | null;
  defaultPurchaseUnit: string | null;
  defaultSaleUnit: string | null;
  hsnCode: string | null;
  itemCode: string | null;
  barcode: string | null;
  publicToken: string | null;
  taxPercent: number | null;
  defaultLandingCost: number | null;
  defaultSellingCost: number | null;
  lastPurchasePrice: number | null;
  lastSellingRate: number | null;
  lastSupplierId: string | null;
  lastBrokerId: string | null;
  lastTradePurchaseId: string | null;
  lastLineQty: number | null;
  lastLineUnit: string | null;
  lastLineWeightKg: number | null;
  lastSupplierName: string | null;
  lastBrokerName: string | null;
  defaultSupplierIds: string[];
  defaultBrokerIds: string[];
  lastPurchaseDate: string | null;
  lastPurchaseDelivered: boolean | null;
  unitResolution: Record<string, unknown> | null;
}

export interface CatalogItemCreateRequest {
  categoryId: string;
  typeId?: string;
  name: string;
  defaultUnit?: string;
  defaultKgPerBag?: number;
  defaultItemsPerBox?: number;
  defaultWeightPerTin?: number;
  defaultPurchaseUnit?: string;
  defaultSaleUnit?: string;
  hsnCode?: string;
  itemCode?: string;
  barcode?: string;
  taxPercent?: number;
  defaultLandingCost?: number;
  defaultSellingCost?: number;
  defaultSupplierIds?: string[];
  defaultBrokerIds?: string[];
  packageType?: string;
}

export interface CatalogItemUpdateRequest {
  categoryId?: string;
  typeId?: string;
  name?: string;
  defaultUnit?: string;
  defaultKgPerBag?: number;
  defaultItemsPerBox?: number;
  defaultWeightPerTin?: number;
  defaultPurchaseUnit?: string;
  defaultSaleUnit?: string;
  hsnCode?: string;
  taxPercent?: number;
  defaultLandingCost?: number;
  defaultSellingCost?: number;
  defaultSupplierIds?: string[];
  defaultBrokerIds?: string[];
  reorderLevel?: number;
}

export async function listCatalogItems(
  businessId: string,
  params?: { categoryId?: string; typeId?: string; perPage?: number; fetchAllPages?: boolean }
): Promise<CatalogItem[]> {
  const res = await api.get(`/businesses/${businessId}/catalog-items`, { params });
  return res.data;
}

export async function getCatalogItem(businessId: string, itemId: string): Promise<CatalogItem> {
  const res = await api.get(`/businesses/${businessId}/catalog-items/${itemId}`);
  return res.data;
}

export async function createCatalogItem(businessId: string, body: CatalogItemCreateRequest): Promise<CatalogItem> {
  const res = await api.post(`/businesses/${businessId}/catalog-items`, body);
  return res.data;
}

export async function updateCatalogItem(businessId: string, itemId: string, body: CatalogItemUpdateRequest): Promise<CatalogItem> {
  const res = await api.patch(`/businesses/${businessId}/catalog-items/${itemId}`, body);
  return res.data;
}

export async function deleteCatalogItem(businessId: string, itemId: string): Promise<void> {
  await api.delete(`/businesses/${businessId}/catalog-items/${itemId}`);
}

export async function createCatalogItemFromScan(
  businessId: string,
  body: { barcode: string; itemCode: string; name: string; typeId: string; defaultUnit?: string; defaultKgPerBag?: number }
): Promise<CatalogItem> {
  const res = await api.post(`/businesses/${businessId}/catalog-items/from-scan`, body);
  return res.data;
}

export async function generateCatalogItemCode(businessId: string, itemId: string): Promise<{ itemCode: string }> {
  const res = await api.post(`/businesses/${businessId}/catalog-items/${itemId}/generate-code`);
  return res.data;
}

export async function patchCatalogItemCode(businessId: string, itemId: string, itemCode: string): Promise<void> {
  await api.patch(`/businesses/${businessId}/catalog-items/${itemId}/item-code`, { itemCode });
}

export async function patchCatalogItemBarcode(businessId: string, itemId: string, barcode: string): Promise<void> {
  await api.patch(`/businesses/${businessId}/catalog-items/${itemId}/barcode`, { barcode });
}

// ─── Variants ───────────────────────────────────────────────
export interface CatalogVariant {
  id: string;
  catalogItemId: string;
  name: string;
  defaultKgPerBag: number | null;
}

export async function listVariants(businessId: string, itemId: string): Promise<CatalogVariant[]> {
  const res = await api.get(`/businesses/${businessId}/catalog-items/${itemId}/variants`);
  return res.data;
}

export async function createVariant(businessId: string, itemId: string, name: string, defaultKgPerBag?: number): Promise<CatalogVariant> {
  const res = await api.post(`/businesses/${businessId}/catalog-items/${itemId}/variants`, { name, defaultKgPerBag });
  return res.data;
}

export async function updateVariant(businessId: string, variantId: string, name?: string, defaultKgPerBag?: number): Promise<CatalogVariant> {
  const res = await api.patch(`/businesses/${businessId}/catalog-items/${variantId}`, { name, defaultKgPerBag });
  return res.data;
}

export async function deleteVariant(businessId: string, variantId: string): Promise<void> {
  await api.delete(`/businesses/${businessId}/catalog-items/${variantId}`);
}

// ─── Insights & Lines ───────────────────────────────────────
export interface CatalogItemInsights {
  lineCount: number;
  entryCount: number;
  totalProfit: number;
  avgLanding: number | null;
  avgSelling: number | null;
  lastEntryDate: string | null;
  profitMarginPct: number | null;
}

export async function getCatalogItemInsights(businessId: string, itemId: string, from?: string, to?: string): Promise<CatalogItemInsights> {
  const res = await api.get(`/businesses/${businessId}/catalog-items/${itemId}/insights`, { params: { from, to } });
  return res.data;
}

export interface CatalogItemLineRow {
  entryId: string;
  entryDate: string;
  qty: number;
  unit: string;
  landingCost: number;
  sellingPrice: number | null;
  profit: number | null;
  supplierName: string | null;
  supplierPhone: string | null;
  brokerName: string | null;
  brokerPhone: string | null;
  purchaseHumanId: string | null;
  kgPerUnit: number | null;
  landingCostPerKg: number | null;
  unitResolution: Record<string, unknown> | null;
}

export async function getCatalogItemLines(businessId: string, itemId: string, params?: { from?: string; to?: string; limit?: number; offset?: number }): Promise<CatalogItemLineRow[]> {
  const res = await api.get(`/businesses/${businessId}/catalog-items/${itemId}/lines`, { params });
  return res.data;
}

// ─── Suppliers Prices ───────────────────────────────────────
export interface TradeSupplierPriceRow {
  supplierId: string;
  supplierName: string;
  landingCost: number;
  unit: string;
  lastPurchaseDate: string;
  isBest: boolean;
  deals: number;
  volumeWeightedLanding: number | null;
}

export interface CatalogItemTradeSupplierPrices {
  catalogItemId: string;
  suppliers: TradeSupplierPriceRow[];
  lastFiveLandingPrices: number[];
  avgLandingFromTrade: number | null;
}

export async function getCatalogItemTradeSupplierPrices(businessId: string, itemId: string): Promise<CatalogItemTradeSupplierPrices> {
  const res = await api.get(`/businesses/${businessId}/catalog-items/${itemId}/trade-supplier-prices`);
  return res.data;
}

// ─── Fuzzy Check ────────────────────────────────────────────
export interface CatalogFuzzyHit {
  id: string;
  name: string;
  score: number;
}

export async function catalogFuzzyCheck(businessId: string, name: string, supplierId?: string, categoryId?: string, typeId?: string): Promise<CatalogFuzzyHit[]> {
  const res = await api.get(`/businesses/${businessId}/catalog/fuzzy-check`, { params: { name, supplierId, categoryId, typeId } });
  return res.data;
}

// ─── Bulk ───────────────────────────────────────────────────
export interface CatalogDuplicatePair {
  idA: string;
  nameA: string;
  idB: string;
  nameB: string;
  score: number;
}

export async function getCatalogDuplicateClusters(businessId: string, minScore?: number): Promise<CatalogDuplicatePair[]> {
  const res = await api.get(`/businesses/${businessId}/catalog/duplicate-clusters`, { params: { minScore } });
  return res.data;
}

export async function bulkArchiveCatalogItems(businessId: string, itemIds: string[]): Promise<void> {
  await api.post(`/businesses/${businessId}/catalog/items/bulk-archive`, { itemIds });
}

export async function bulkReorderCatalogItems(businessId: string, itemIds: string[], reorderLevel: number): Promise<void> {
  await api.patch(`/businesses/${businessId}/catalog/items/bulk-reorder`, { itemIds, reorderLevel });
}
