using PurchaseAssistant.Application.DTOs;

namespace PurchaseAssistant.Application.Interfaces;

public interface IStockService
{
    // Stock List
    Task<StockListOut> GetStockListAsync(Guid businessId, Guid? categoryId, Guid? typeId, bool? lowStock, string? q, int page, int perPage, string actorRole, CancellationToken ct = default);
    Task<StockShellBundleOut> GetShellBundleAsync(Guid businessId, string actorRole, CancellationToken ct = default);
    Task<StockDeliveryIndicatorCountsOut> GetDeliveryIndicatorCountsAsync(Guid businessId, CancellationToken ct = default);
    Task<StockListCompactOut> GetCompactListAsync(Guid businessId, CancellationToken ct = default);
    Task<List<StockSearchHit>> SearchStockAsync(Guid businessId, string q, int limit = 20, CancellationToken ct = default);
    Task<StockAlertsSummaryOut> GetAlertsSummaryAsync(Guid businessId, CancellationToken ct = default);
    Task<WarehouseAlertsSummaryOut> GetWarehouseAlertsSummaryAsync(Guid businessId, CancellationToken ct = default);
    Task<LowStockOpsOut> GetLowStockOperationsAsync(Guid businessId, int page, int perPage, CancellationToken ct = default);

    // Stock Detail
    Task<StockDetailOut> GetStockDetailAsync(Guid businessId, Guid itemId, CancellationToken ct = default);
    Task<StockIntelligenceOut> GetStockIntelligenceAsync(Guid businessId, Guid itemId, CancellationToken ct = default);
    Task<StockItemActivityOut> GetStockActivityAsync(Guid businessId, Guid itemId, int limit = 50, CancellationToken ct = default);

    // Stock Mutations
    Task<StockMovementOut> CreateAdjustmentAsync(Guid businessId, CreateStockAdjustmentRequest request, Guid actorId, string actorName, CancellationToken ct = default);
    Task<StockMovementOut> CreateMovementAsync(Guid businessId, StockMovementCreateIn request, Guid actorId, string actorName, CancellationToken ct = default);
    Task<PhysicalStockCountOut> CreatePhysicalCountAsync(Guid businessId, PhysicalStockCountIn request, Guid actorId, string actorName, CancellationToken ct = default);
    Task<StockPhysicalUpdateOut> PhysicalUpdateAsync(Guid businessId, Guid itemId, StockPhysicalUpdateIn request, Guid actorId, string actorName, CancellationToken ct = default);
    Task<StockVerifyCountOut> VerifyCountAsync(Guid businessId, Guid itemId, StockVerifyCountIn request, Guid actorId, string actorName, CancellationToken ct = default);
    Task<StockDetailOut> PatchStockItemAsync(Guid businessId, Guid itemId, DTOs.Stock.StockPatchIn request, Guid actorId, string actorName, string actorRole, CancellationToken ct = default);
    Task<StockMovementOut?> UndoLastAsync(Guid businessId, Guid itemId, Guid actorId, string actorName, CancellationToken ct = default);
    Task NotifyOwnerAsync(Guid businessId, Guid itemId, NotifyOwnerIn request, Guid actorId, CancellationToken ct = default);
    Task<QuickPurchaseOut> CreateQuickPurchaseAsync(Guid businessId, Guid itemId, QuickPurchaseIn request, Guid actorId, CancellationToken ct = default);

    // Opening Stock
    Task<OpeningStockSetupOut> GetOpeningStockSetupAsync(Guid businessId, string? status, string? q, int page, int perPage, CancellationToken ct = default);
    Task<OpeningStockMissingOut> GetOpeningStockMissingAsync(Guid businessId, CancellationToken ct = default);
    Task<StockMovementOut> SetOpeningStockAsync(Guid businessId, Guid itemId, OpeningStockIn request, Guid actorId, string actorName, CancellationToken ct = default);

    // Inventory / Totals
    Task<InventorySummaryOut> GetInventorySummaryAsync(Guid businessId, CancellationToken ct = default);
    Task<StockTotalsOut> GetStockTotalsAsync(Guid businessId, CancellationToken ct = default);

    // Reorder
    Task<ReorderListOut> GetReorderListAsync(Guid businessId, CancellationToken ct = default);
    Task PatchReorderEntryAsync(Guid businessId, Guid entryId, ReorderListPatchIn request, CancellationToken ct = default);
    Task DeleteReorderEntryAsync(Guid businessId, Guid entryId, CancellationToken ct = default);
    Task<ReorderListEntryOut> AddToReorderListAsync(Guid businessId, Guid itemId, Guid actorId, CancellationToken ct = default);

    // Barcode
    Task<BarcodeLookupOut?> BarcodeLookupAsync(Guid businessId, string barcode, CancellationToken ct = default);
    Task<BarcodeLabelOut> GetBarcodeLabelAsync(Guid businessId, Guid itemId, CancellationToken ct = default);
    Task<BarcodeBatchOut> BatchBarcodeLabelsAsync(Guid businessId, BarcodeBatchIn request, CancellationToken ct = default);

    // Audit / Activity
    Task<List<StockAuditFeedItemOut>> GetAuditFeedAsync(Guid businessId, int limit = 50, CancellationToken ct = default);
    Task<List<StockAdjustmentOut>> GetRecentAdjustmentsAsync(Guid businessId, int limit = 20, CancellationToken ct = default);
    Task<List<StockVarianceOut>> GetTodayVariancesAsync(Guid businessId, CancellationToken ct = default);
    Task<List<StockAdjustmentOut>> GetItemAuditAsync(Guid businessId, Guid itemId, int limit = 50, CancellationToken ct = default);
    Task<List<StockMovementOut>> GetMovementsAsync(Guid businessId, Guid? itemId, int limit = 50, CancellationToken ct = default);
    Task<List<PhysicalStockCountOut>> GetPhysicalCountsAsync(Guid businessId, Guid? itemId, int limit = 50, CancellationToken ct = default);
    Task<List<StaffPurchaseLogOut>> GetStaffPurchasesAsync(Guid businessId, int limit = 50, CancellationToken ct = default);
    Task<StaffPurchaseLogOut> CreateStaffPurchaseAsync(Guid businessId, StaffPurchaseLogIn request, Guid actorId, string actorName, CancellationToken ct = default);
}

public record StockMovementCreateIn(
    Guid ItemId, decimal Qty, string? Unit,
    string? FromLocation, string? ToLocation,
    string? Notes
);
