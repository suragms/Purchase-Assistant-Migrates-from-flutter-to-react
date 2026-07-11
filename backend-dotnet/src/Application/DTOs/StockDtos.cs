namespace PurchaseAssistant.Application.DTOs;

// ─── Stock List ─────────────────────────────────────────────
public record StockListItemOut(
    Guid Id, string Name, string? ItemCode, string? Barcode,
    string? CategoryName, string? TypeName, string? DefaultUnit,
    decimal CurrentStock, decimal? ReorderLevel, string? StockUnit,
    string? DisplayUnit, string? PackageType, string? ValidationStatus,
    decimal? LastPurchasePrice, decimal? DefaultLandingCost,
    decimal? DefaultSellingCost,
    Guid? LastSupplierId, string? LastSupplierName,
    DateTime? LastPurchaseDate,
    int? DaysSinceLastPurchase,
    string? Status,
    decimal? PendingOrderQty, bool HasPendingOrder,
    decimal? PeriodPurchased, decimal? PeriodUsage,
    decimal? PhysicalCountVariance, bool NeedsVerification,
    DateTime? LastMovementAt, int? StockVersion,
    string? RackLocation, string? LastStockUpdatedBy
);

public record StockListOut(
    List<StockListItemOut> Items, int TotalCount
);

public record StockListItemMinimalOut(Guid Id, string Name, string? ItemCode, string? Barcode, decimal CurrentStock);

public record StockListCompactOut(List<StockListItemMinimalOut> Items);

public record StockDeliveryIndicatorCountsOut(
    int Pending, int DeliveredToday, int DeliveredPendingScan,
    int TotalDispatched, int TotalArrived
);

// ─── Stock Search ───────────────────────────────────────────
public record StockSearchHit(Guid Id, string Name, string? ItemCode, string? Barcode, decimal CurrentStock, string? CategoryName);

// ─── Alerts ─────────────────────────────────────────────────
public record StockAlertsSummaryOut(
    int LowStock, int Critical, int OutOfStock, int Overstock,
    int PendingVerification, int Disputed
);

public record WarehouseAlertsSummaryOut(
    int TotalAlerts, int LowStock, int OutOfStock,
    int PendingDelivery, int PendingVerification,
    int Disputed, int RecentAudit
);

// ─── Low Stock Operations ───────────────────────────────────
public record LowStockOpsSummaryOut(
    int ShortageItems, int OutOfStockItems,
    int DelayedItems, int MismatchItems,
    int VerificationNeeded
);

public record LowStockOpsItemOut(
    Guid Id, string Name, string? ItemCode, string? Barcode,
    string? CategoryName, string? DefaultUnit,
    decimal CurrentStock, decimal? ReorderLevel,
    decimal Shortage, double PriorityScore,
    string Band, bool OutOfStock, bool Delayed,
    bool Mismatch, bool NeedsVerification,
    string? LifecycleStage,
    decimal? LastPurchasePrice, Guid? LastSupplierId, string? LastSupplierName,
    DateTime? LastPurchaseDate, DateTime? LastMovementAt
);

public record LowStockOpsOut(
    LowStockOpsSummaryOut Summary,
    List<LowStockOpsItemOut> Items, int TotalCount
);

// ─── Shell Bundle ───────────────────────────────────────────
public record StockShellBundleOut(
    List<StockListItemOut> Items,
    StockDeliveryIndicatorCountsOut DeliveryCounts,
    StockAlertsSummaryOut Alerts,
    List<StockActivityEventOut> RecentActivity
);

// ─── Detail ─────────────────────────────────────────────────
public record StockDetailOut(
    Guid Id, string Name, string? ItemCode, string? Barcode,
    string? CategoryName, string? TypeName,
    string? DefaultUnit, string? StockUnit, string? DisplayUnit,
    string? PackageType, string? HsnCode,
    decimal CurrentStock, decimal? ReorderLevel,
    decimal? OpeningStock, bool OpeningStockLocked,
    decimal? DefaultLandingCost, decimal? DefaultSellingCost,
    decimal? LastPurchasePrice, decimal? LastSellingRate,
    decimal? TotalMovementIn, decimal? TotalMovementOut,
    Guid? LastSupplierId, string? LastSupplierName,
    Guid? LastBrokerId, string? LastBrokerName,
    DateTime? LastPurchaseDate, DateTime? LastStockUpdatedAt,
    int StockVersion, string? ValidationStatus,
    string? RackLocation, string? PublicToken,
    List<Guid> DefaultSupplierIds, List<Guid> DefaultBrokerIds
);

// ─── Stock Intelligence ─────────────────────────────────────
public record StockIntelligenceOut(
    decimal? SuggestedQty, int? AvgIntervalDays,
    Guid? DefaultSupplierId, string? DefaultSupplierName,
    decimal? AvgLandingCost, decimal? AvgSellingRate,
    decimal? PeriodUsage, decimal? PeriodPurchased,
    int DaysSinceLastPurchase
);

// ─── Stock Activity ─────────────────────────────────────────
public record StockActivityEventOut(
    Guid Id, string Kind, decimal DeltaQty, decimal? QtyBefore, decimal? QtyAfter,
    string? Unit, string? Reason, string? ActorName,
    DateTimeOffset? CreatedAt
);

public record StockItemActivityOut(
    Guid ItemId, List<StockActivityEventOut> Events
);

// ─── Stock Movement ─────────────────────────────────────────
public record StockMovementOut(
    Guid Id, Guid ItemId, string MovementKind, decimal DeltaQty,
    decimal? QtyBefore, decimal? QtyAfter, string? StockUnit,
    string? Reason, string? Notes, string? SourceType, Guid? SourceId,
    string? ActorName, DateTimeOffset? CreatedAt
);

// ─── Physical Count ─────────────────────────────────────────
public record PhysicalStockCountIn(
    Guid ItemId, decimal CountedQty, string? StockUnit,
    string? Notes, string? IdempotencyKey
);

public record PhysicalStockCountOut(
    Guid Id, Guid ItemId, decimal SystemQty, decimal CountedQty,
    decimal DifferenceQty, string? StockUnit, string? Notes,
    string? CountedByName, DateTimeOffset CountedAt
);

// ─── Physical Update ────────────────────────────────────────
public record StockPhysicalUpdateIn(
    decimal CountedQty, int ExpectedVersion, string? Reason
);

public record StockPhysicalUpdateOut(
    Guid ItemId, decimal OldStock, decimal NewStock,
    decimal Difference, int NewVersion
);

// ─── Opening Stock ──────────────────────────────────────────
public record OpeningStockIn(decimal Qty, string? Reason);

public record OpeningStockSetupItemOut(
    Guid Id, string Name, string? DefaultUnit,
    decimal? OpeningStock, bool OpeningStockLocked,
    string? Status
);

public record OpeningStockSetupOut(
    List<OpeningStockSetupItemOut> Items, int TotalCount
);

public record OpeningStockMissingOut(
    List<OpeningStockSetupItemOut> Items, int TotalCount
);

// ─── Stock Adjustment ───────────────────────────────────────
public record StockAdjustmentOut(
    Guid Id, Guid ItemId, string ItemName,
    decimal OldQty, decimal NewQty,
    string AdjustmentType, string? Reason,
    Guid? UpdatedBy, string? UpdatedByName,
    DateTimeOffset UpdatedAt
);

public record CreateStockAdjustmentRequest(Guid CatalogItemId, string AdjustmentType, decimal Qty, string? Unit, string? Reason);

// ─── Inventory Summary ──────────────────────────────────────
public record InventorySummaryItemOut(
    string? CategoryName, int ItemCount,
    decimal TotalStock, decimal TotalValue
);

public record InventorySummaryOut(
    List<InventorySummaryItemOut> Categories,
    decimal GrandTotalStock, decimal GrandTotalValue
);

// ─── Stock Totals ───────────────────────────────────────────
public record StockTotalsItemOut(string Unit, decimal TotalQty, int ItemCount);

public record StockTotalsOut(List<StockTotalsItemOut> Items);

// ─── Reorder ────────────────────────────────────────────────
public record ReorderListEntryOut(
    Guid Id, Guid ItemId, string ItemName, string? ItemCode,
    string? DefaultUnit, decimal CurrentStock, decimal? ReorderLevel,
    string? LastSupplierName, decimal? LastPurchasePrice,
    DateTime? LastPurchaseDate, string Status,
    DateTimeOffset CreatedAt
);

public record ReorderListOut(List<ReorderListEntryOut> Items);

public record ReorderListPatchIn(string? Status, string? Notes);

// ─── Quick Purchase ─────────────────────────────────────────
public record QuickPurchaseIn(
    Guid SupplierId, decimal Qty, decimal? Rate,
    string? Unit, string? Notes
);

public record QuickPurchaseOut(
    Guid PurchaseId, Guid ItemId, decimal Qty, decimal? Rate,
    decimal? TotalAmount, string Status
);

// ─── Barcode ────────────────────────────────────────────────
public record BarcodeLookupOut(
    Guid ItemId, string Name, string? ItemCode, string? Barcode,
    decimal CurrentStock, string? DefaultUnit,
    Guid? CategoryId, string? CategoryName,
    Guid? TypeId, string? TypeName,
    decimal? LandingCost, decimal? SellingCost
);

public record BarcodeLabelOut(
    Guid ItemId, string Name, string? Barcode, string? ItemCode,
    decimal? LandingCost, decimal? SellingCost
);

public record BarcodeBatchIn(List<Guid> ItemIds);

public record BarcodeBatchOut(List<BarcodeLabelOut> Items);

// ─── Verify Count ───────────────────────────────────────────
public record StockVerifyCountIn(decimal CountedQty);

public record StockVerifyCountOut(
    Guid ItemId, decimal SystemQty, decimal CountedQty,
    decimal Difference, bool Match
);

// ─── Notify Owner ───────────────────────────────────────────
public record NotifyOwnerIn(string? Message);

// ─── Staff Purchase Log ─────────────────────────────────────
public record StaffPurchaseLogIn(
    Guid CatalogItemId, decimal Qty, decimal? Rate,
    string? Unit, string? SupplierName, string? Notes
);

public record StaffPurchaseLogOut(
    Guid Id, Guid ItemId, string ItemName,
    decimal Qty, decimal? Rate, string? Unit,
    string? SupplierName, string? Notes,
    string? CreatedBy, DateTimeOffset CreatedAt
);

// ─── Variances ──────────────────────────────────────────────
public record StockVarianceOut(
    Guid ItemId, string ItemName, decimal SystemQty,
    decimal? PhysicalQty, decimal? PurchasedQty,
    decimal Variance, bool Material
);

// ─── Audit Feed ─────────────────────────────────────────────
public record StockAuditFeedItemOut(
    Guid Id, Guid ItemId, string ItemName,
    string AdjustmentType, decimal OldQty, decimal NewQty,
    string? Reason, string? UpdatedByName,
    DateTimeOffset UpdatedAt
);
