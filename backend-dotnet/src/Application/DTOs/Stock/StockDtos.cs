namespace PurchaseAssistant.Application.DTOs.Stock;

public record StockPatchIn(decimal NewQty, string AdjustmentType = "verification", string? Reason = null, int? LastSeenStockVersion = null, string? IdempotencyKey = null);
public record StockPhysicalUpdateIn(decimal CountedQty, string AdjustmentType = "verification", string? Reason = null, string? Notes = null, int? LastSeenStockVersion = null, string? IdempotencyKey = null);

public record StockListItemOut(Guid Id, string Name, string? ItemCode, string? Barcode, string? CategoryName, decimal CurrentStock, decimal ReorderLevel, string StockStatus, int StockVersion);
public record StockListOut(List<StockListItemOut> Items, int Total, int Page, int PerPage);
public record StockListCompactOut(List<StockListItemMinimalOut> Items, int Total, int Page, int PerPage);
public record StockListItemMinimalOut(Guid Id, string Name, string? ItemCode, string? Barcode, decimal CurrentStock, string StockUnit, string StockStatus, decimal ReorderLevel);

public record StockDetailOut(Guid Id, string Name, string? ItemCode, string? Barcode, string? CategoryName, decimal CurrentStock, decimal ReorderLevel, string StockStatus, int StockVersion);
public record StockAlertsSummaryOut(int LowStock = 0, int CriticalStock = 0, int OutOfStock = 0, int MissingBarcode = 0, int TotalItems = 0);
public record WarehouseAlertsSummaryOut(int PendingDeliveries = 0, int LowStock = 0, int CriticalStock = 0, int PendingVerifications = 0, int MissingBarcode = 0);

public record StockShellBundleOut(StockListOut List, StockAlertsSummaryOut StatusCounts, StockDeliveryIndicatorCountsOut DeliveryCounts);
public record StockDeliveryIndicatorCountsOut(int Pending = 0, int Delivered = 0);

public record PhysicalStockCountIn(decimal CountedQty, string? Notes = null, string? IdempotencyKey = null);
public record PhysicalStockCountOut(Guid Id, Guid ItemId, decimal SystemQty, decimal CountedQty, decimal DifferenceQty, DateTime CountedAt);

public record OpeningStockIn(decimal Qty, bool Override = false, string? Reason = null, string? IdempotencyKey = null);
public record OpeningStockSetupOut(object Summary, List<StockListItemOut> Items, int Total, int Page, int PerPage);

public record StockMovementOut(Guid Id, Guid ItemId, decimal? Qty, string? Unit, string? Notes, DateTime CreatedAt);
public record StockPhysicalUpdateOut(StockDetailOut Item, StockMovementOut Movement);

public record QuickPurchaseIn(decimal Qty, Guid SupplierId, Guid? BrokerId = null, string? Notes = null, string? IdempotencyKey = null);
public record QuickPurchaseOut(object PurchaseLog, StockMovementOut Movement, StockDetailOut Item);

public record StaffPurchaseLogIn(Guid ItemId, decimal Qty, decimal? Amount = null, Guid? SupplierId = null, string? SupplierName = null, Guid? BrokerId = null, string? Notes = null, string? IdempotencyKey = null);
public record StaffPurchaseLogOut(Guid Id, Guid ItemId, string ItemName, decimal Qty, decimal? Amount, DateTime CreatedAt);

public record InventorySummaryOut(double TotalValueInr, double Bags, double Boxes, double Tins, double Kg, int ItemCount);
public record StockTotalsOut(double TotalBags, double TotalKg, double TotalBoxes, double TotalTins, int TotalItems);

public record BarcodeLookupOut(Guid Id, string Name, string? ItemCode, string? Barcode, decimal CurrentStock, decimal ReorderLevel);
public record BarcodeLabelOut(Guid Id, string? Barcode, string? ItemCode, string ItemName, string? CategoryName);
public record BarcodeBatchIn(List<Guid> ItemIds);
public record BarcodeBatchOut(List<BarcodeLabelOut> Labels);

public record ReorderListEntryOut(Guid Id, Guid ItemId, string ItemName, decimal CurrentStock, decimal ReorderLevel, string Status, DateTime CreatedAt);
public record ReorderListOut(List<ReorderListEntryOut> Items, int Total);
public record ReorderListPatchIn(string Status);
