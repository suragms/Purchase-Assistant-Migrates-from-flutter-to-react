namespace PurchaseAssistant.Application.DTOs.Stock;

public class StockItemDto
{
    public Guid Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public string? ItemCode { get; set; }
    public string? Barcode { get; set; }
    public string? CategoryName { get; set; }
    public string? TypeName { get; set; }
    public string? DefaultUnit { get; set; }
    public decimal CurrentStock { get; set; }
    public decimal? ReorderLevel { get; set; }
    public decimal? LastPurchasePrice { get; set; }
    public decimal? DefaultLandingCost { get; set; }
    public decimal? DefaultSellingCost { get; set; }
    public string? LastSupplierName { get; set; }
    public DateTime? LastPurchaseDate { get; set; }
    public string? Status { get; set; }
}

public class StockListResponse
{
    public List<StockItemDto> Items { get; set; } = new();
    public int TotalCount { get; set; }
}

public class StockDetailDto
{
    public Guid Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public string? ItemCode { get; set; }
    public string? Barcode { get; set; }
    public string? CategoryName { get; set; }
    public string? TypeName { get; set; }
    public string? DefaultUnit { get; set; }
    public decimal CurrentStock { get; set; }
    public decimal? ReorderLevel { get; set; }
    public decimal? OpeningStock { get; set; }
    public bool OpeningStockLocked { get; set; }
    public decimal? DefaultLandingCost { get; set; }
    public decimal? DefaultSellingCost { get; set; }
    public decimal? LastPurchasePrice { get; set; }
    public decimal? LastSellingRate { get; set; }
    public decimal? TotalMovementIn { get; set; }
    public decimal? TotalMovementOut { get; set; }
    public Guid? LastSupplierId { get; set; }
    public string? LastSupplierName { get; set; }
    public DateTime? LastPurchaseDate { get; set; }
    public int StockVersion { get; set; }
    public string? ValidationStatus { get; set; }
    public List<Guid> DefaultSupplierIds { get; set; } = new();
    public List<Guid> DefaultBrokerIds { get; set; } = new();
}

public class StockAdjustRequest
{
    public string AdjustmentType { get; set; } = string.Empty;
    public decimal Qty { get; set; }
    public string? Unit { get; set; }
    public string? Reason { get; set; }
}

public class StockMovementDto
{
    public Guid Id { get; set; }
    public Guid ItemId { get; set; }
    public string MovementKind { get; set; } = string.Empty;
    public decimal DeltaQty { get; set; }
    public decimal QtyBefore { get; set; }
    public decimal QtyAfter { get; set; }
    public string? StockUnit { get; set; }
    public string? Reason { get; set; }
    public string? SourceType { get; set; }
    public Guid? SourceId { get; set; }
    public string? ActorName { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
}

public class StockMovementRequest
{
    public Guid ItemId { get; set; }
    public decimal DeltaQty { get; set; }
    public string? Reason { get; set; }
    public string? Notes { get; set; }
}

public class PhysicalCountRequest
{
    public Guid ItemId { get; set; }
    public decimal CountedQty { get; set; }
    public string? StockUnit { get; set; }
    public string? Notes { get; set; }
    public string? IdempotencyKey { get; set; }
}

public class PhysicalCountDto
{
    public Guid Id { get; set; }
    public Guid ItemId { get; set; }
    public decimal SystemQty { get; set; }
    public decimal CountedQty { get; set; }
    public decimal DifferenceQty { get; set; }
    public string? StockUnit { get; set; }
    public string? Notes { get; set; }
    public string? CountedByName { get; set; }
    public DateTimeOffset CountedAt { get; set; }
}

public class StockSummaryDto
{
    public int TotalItems { get; set; }
    public decimal TotalStockQty { get; set; }
    public decimal TotalStockValue { get; set; }
    public int LowStockCount { get; set; }
    public int OutOfStockCount { get; set; }
    public int OverstockCount { get; set; }
}

public class ReorderItemDto
{
    public Guid Id { get; set; }
    public Guid ItemId { get; set; }
    public string ItemName { get; set; } = string.Empty;
    public string? ItemCode { get; set; }
    public string? DefaultUnit { get; set; }
    public decimal CurrentStock { get; set; }
    public decimal? ReorderLevel { get; set; }
    public string? LastSupplierName { get; set; }
    public decimal? LastPurchasePrice { get; set; }
    public DateTime? LastPurchaseDate { get; set; }
    public string Status { get; set; } = string.Empty;
    public DateTimeOffset CreatedAt { get; set; }
}
