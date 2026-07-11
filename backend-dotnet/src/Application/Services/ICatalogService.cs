using PurchaseAssistant.Application.DTOs.Catalog;

namespace PurchaseAssistant.Application.Services;

public interface ICatalogService
{
    Task<List<ItemCategoryOut>> GetCategoriesAsync(Guid businessId, CancellationToken ct = default);
    Task<ItemCategoryOut> CreateCategoryAsync(Guid businessId, ItemCategoryCreateRequest request, CancellationToken ct = default);
    Task<ItemCategoryOut> GetCategoryAsync(Guid businessId, Guid categoryId, CancellationToken ct = default);
    Task<ItemCategoryOut> UpdateCategoryAsync(Guid businessId, Guid categoryId, ItemCategoryUpdateRequest request, CancellationToken ct = default);
    Task DeleteCategoryAsync(Guid businessId, Guid categoryId, CancellationToken ct = default);
    Task<CategoryTradeSummaryOut> GetCategoryTradeSummaryAsync(Guid businessId, Guid categoryId, CancellationToken ct = default);
    Task<CategoryInsightsOut> GetCategoryInsightsAsync(Guid businessId, Guid categoryId, DateOnly from, DateOnly to, CancellationToken ct = default);

    Task<List<CategoryTypeOut>> GetCategoryTypesAsync(Guid businessId, Guid categoryId, CancellationToken ct = default);
    Task<CategoryTypeOut> CreateCategoryTypeAsync(Guid businessId, Guid categoryId, CategoryTypeCreateRequest request, CancellationToken ct = default);
    Task<CategoryTypeOut> UpdateCategoryTypeAsync(Guid businessId, Guid categoryId, Guid typeId, CategoryTypeUpdateRequest request, CancellationToken ct = default);
    Task DeleteCategoryTypeAsync(Guid businessId, Guid categoryId, Guid typeId, CancellationToken ct = default);
    Task<List<CategoryTypeIndexOut>> GetCategoryTypesIndexAsync(Guid businessId, CancellationToken ct = default);

    Task<List<CatalogItemOut>> GetItemsAsync(Guid businessId, Guid? categoryId, Guid? typeId, int page, int perPage, CancellationToken ct = default);
    Task<CatalogItemOut> GetItemAsync(Guid businessId, Guid itemId, CancellationToken ct = default);
    Task<CatalogItemOut> CreateItemAsync(Guid businessId, CatalogItemCreateRequest request, Guid actorUserId, string actorRole, CancellationToken ct = default);
    Task<CatalogItemOut> CreateItemFromScanAsync(Guid businessId, CatalogItemFromScanRequest request, Guid actorUserId, CancellationToken ct = default);
    Task<CatalogBatchOut> BatchCreateItemsAsync(Guid businessId, CatalogBatchCreateRequest request, Guid actorUserId, CancellationToken ct = default);
    Task<CatalogItemOut> UpdateItemAsync(Guid businessId, Guid itemId, CatalogItemUpdateRequest request, string actorRole, CancellationToken ct = default);
    Task DeleteItemAsync(Guid businessId, Guid itemId, CancellationToken ct = default);
    Task<CatalogItemOut> PatchItemCodeAsync(Guid businessId, Guid itemId, ItemCodePatchRequest request, CancellationToken ct = default);
    Task<CatalogItemOut> PatchBarcodeAsync(Guid businessId, Guid itemId, BarcodePatchRequest request, CancellationToken ct = default);
    Task<CatalogItemOut> GenerateItemCodeAsync(Guid businessId, Guid itemId, CancellationToken ct = default);

    Task<SupplierPurchaseDefaultsOut> GetSupplierPurchaseDefaultsAsync(Guid businessId, Guid itemId, Guid supplierId, CancellationToken ct = default);
    Task<CatalogItemTradeSupplierPricesOut> GetTradeSupplierPricesAsync(Guid businessId, Guid itemId, CancellationToken ct = default);
    Task<CatalogItemInsightsOut> GetItemInsightsAsync(Guid businessId, Guid itemId, DateOnly from, DateOnly to, CancellationToken ct = default);
    Task<List<CatalogItemLineRow>> GetItemLinesAsync(Guid businessId, Guid itemId, DateOnly from, DateOnly to, int limit, int offset, string actorRole, CancellationToken ct = default);

    Task<CatalogFuzzyCheckResponse> FuzzyCheckAsync(Guid businessId, string name, Guid? supplierId, Guid? categoryId, Guid? typeId, CancellationToken ct = default);
    Task<CatalogDuplicateClustersResponse> GetDuplicateClustersAsync(Guid businessId, double minScore, CancellationToken ct = default);

    Task BulkArchiveItemsAsync(Guid businessId, BulkItemIdsIn request, CancellationToken ct = default);
    Task<int> BulkReorderItemsAsync(Guid businessId, BulkReorderIn request, CancellationToken ct = default);

    Task<List<CatalogVariantOut>> GetVariantsAsync(Guid businessId, Guid itemId, CancellationToken ct = default);
    Task<CatalogVariantOut> CreateVariantAsync(Guid businessId, Guid itemId, CatalogVariantCreateRequest request, CancellationToken ct = default);
    Task<CatalogVariantOut> UpdateVariantAsync(Guid businessId, Guid itemId, Guid variantId, CatalogVariantUpdateRequest request, CancellationToken ct = default);
    Task DeleteVariantAsync(Guid businessId, Guid itemId, Guid variantId, CancellationToken ct = default);
}
