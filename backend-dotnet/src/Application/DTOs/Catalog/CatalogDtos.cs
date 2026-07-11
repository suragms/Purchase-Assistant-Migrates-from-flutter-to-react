using System.ComponentModel.DataAnnotations;

namespace PurchaseAssistant.Application.DTOs.Catalog;

// -- Categories --
public class ItemCategoryOut
{
    public Guid Id { get; set; }
    public string Name { get; set; } = string.Empty;
}

public class ItemCategoryCreateRequest
{
    [StringLength(255)]
    public string Name { get; set; } = string.Empty;
}

public class ItemCategoryUpdateRequest
{
    [StringLength(255)]
    public string? Name { get; set; }
}

// -- Category Types --
public class CategoryTypeOut
{
    public Guid Id { get; set; }
    public Guid CategoryId { get; set; }
    public string Name { get; set; } = string.Empty;
}

public class CategoryTypeCreateRequest
{
    [StringLength(255)]
    public string Name { get; set; } = string.Empty;
}

public class CategoryTypeUpdateRequest
{
    [StringLength(255)]
    public string? Name { get; set; }
}

public class CategoryTypeIndexOut
{
    public Guid Id { get; set; }
    public Guid CategoryId { get; set; }
    public string CategoryName { get; set; } = string.Empty;
    public string Name { get; set; } = string.Empty;
}

// -- Catalog Items --
public class CatalogItemOut
{
    public Guid Id { get; set; }
    public Guid CategoryId { get; set; }
    public Guid? TypeId { get; set; }
    public string? TypeName { get; set; }
    public string Name { get; set; } = string.Empty;
    public string? DefaultUnit { get; set; }
    public double? DefaultKgPerBag { get; set; }
    public double? DefaultItemsPerBox { get; set; }
    public double? DefaultWeightPerTin { get; set; }
    public string? DefaultPurchaseUnit { get; set; }
    public string? DefaultSaleUnit { get; set; }
    public string? HsnCode { get; set; }
    public string? ItemCode { get; set; }
    public string? Barcode { get; set; }
    public string? PublicToken { get; set; }
    public double? TaxPercent { get; set; }
    public double? DefaultLandingCost { get; set; }
    public double? DefaultSellingCost { get; set; }
    public double? LastPurchasePrice { get; set; }
    public double? LastSellingRate { get; set; }
    public Guid? LastSupplierId { get; set; }
    public Guid? LastBrokerId { get; set; }
    public Guid? LastTradePurchaseId { get; set; }
    public double? LastLineQty { get; set; }
    public string? LastLineUnit { get; set; }
    public double? LastLineWeightKg { get; set; }
    public string? LastSupplierName { get; set; }
    public string? LastBrokerName { get; set; }
    public List<Guid> DefaultSupplierIds { get; set; } = new();
    public List<Guid> DefaultBrokerIds { get; set; } = new();
    public DateOnly? LastPurchaseDate { get; set; }
    public bool? LastPurchaseDelivered { get; set; }
    public Dictionary<string, object>? UnitResolution { get; set; }
}

public class CatalogItemCreateRequest
{
    public Guid CategoryId { get; set; }
    public Guid? TypeId { get; set; }

    [StringLength(512)]
    public string Name { get; set; } = string.Empty;

    [RegularExpression("^(kg|box|piece|bag|tin)$")]
    public string DefaultUnit { get; set; } = "kg";
    public double? DefaultKgPerBag { get; set; }
    public double? DefaultItemsPerBox { get; set; }
    public double? DefaultWeightPerTin { get; set; }
    public string? DefaultPurchaseUnit { get; set; }
    public string? DefaultSaleUnit { get; set; }
    public string? HsnCode { get; set; }
    public string? ItemCode { get; set; }
    public string? Barcode { get; set; }
    public double? TaxPercent { get; set; }
    public double? DefaultLandingCost { get; set; }
    public double? DefaultSellingCost { get; set; }
    public List<Guid> DefaultSupplierIds { get; set; } = new();
    public List<Guid>? DefaultBrokerIds { get; set; }
    public string? PackageType { get; set; }
}

public class CatalogItemUpdateRequest
{
    public Guid? CategoryId { get; set; }
    public Guid? TypeId { get; set; }

    [StringLength(512)]
    public string? Name { get; set; }

    [RegularExpression("^(kg|box|piece|bag|tin)$")]
    public string? DefaultUnit { get; set; }
    public double? DefaultKgPerBag { get; set; }
    public double? DefaultItemsPerBox { get; set; }
    public double? DefaultWeightPerTin { get; set; }
    public string? DefaultPurchaseUnit { get; set; }
    public string? DefaultSaleUnit { get; set; }
    public string? HsnCode { get; set; }
    public double? TaxPercent { get; set; }
    public double? DefaultLandingCost { get; set; }
    public double? DefaultSellingCost { get; set; }
    public List<Guid>? DefaultSupplierIds { get; set; }
    public List<Guid>? DefaultBrokerIds { get; set; }
    public double? ReorderLevel { get; set; }
}

public class CatalogItemFromScanRequest
{
    [StringLength(64)]
    public string Barcode { get; set; } = string.Empty;

    [StringLength(64)]
    public string ItemCode { get; set; } = string.Empty;

    [StringLength(512)]
    public string Name { get; set; } = string.Empty;
    public Guid TypeId { get; set; }

    [RegularExpression("^(kg|box|piece|bag|tin)$")]
    public string DefaultUnit { get; set; } = "kg";
    public double? DefaultKgPerBag { get; set; }
}

public class ItemCodePatchRequest
{
    [StringLength(64)]
    public string ItemCode { get; set; } = string.Empty;
}

public class BarcodePatchRequest
{
    [StringLength(64)]
    public string? Barcode { get; set; }
}

public class CatalogBatchItem
{
    [StringLength(512)]
    public string Name { get; set; } = string.Empty;
    public Guid TypeId { get; set; }

    [RegularExpression("^(kg|box|piece|bag|tin)$")]
    public string DefaultUnit { get; set; } = "kg";
    public double? DefaultKgPerBag { get; set; }
    public double? DefaultItemsPerBox { get; set; }
    public double? DefaultWeightPerTin { get; set; }
    public List<Guid> DefaultSupplierIds { get; set; } = new();
    public string? PackageType { get; set; }
}

public class CatalogBatchCreateRequest
{
    public List<CatalogBatchItem> Items { get; set; } = new();
}

public class CatalogBatchOut
{
    public int Created { get; set; }
    public int Skipped { get; set; }
    public List<CatalogItemOut> Items { get; set; } = new();
}

// -- Supplier defaults --
public class SupplierPurchaseDefaultsOut
{
    public Guid CatalogItemId { get; set; }
    public Guid SupplierId { get; set; }
    public double? LastPrice { get; set; }
    public double? LastDiscount { get; set; }
    public int? LastPaymentDays { get; set; }
    public int PurchaseCount { get; set; }
    public string? ItemHsnCode { get; set; }
    public double? ItemTaxPercent { get; set; }
    public string? ItemDefaultUnit { get; set; }
    public double? ItemDefaultKgPerBag { get; set; }
    public double? ItemDefaultLandingCost { get; set; }
    public string? ItemDefaultPurchaseUnit { get; set; }
}

// -- Trade supplier prices --
public class TradeSupplierPriceRow
{
    public Guid SupplierId { get; set; }
    public string SupplierName { get; set; } = string.Empty;
    public double LandingCost { get; set; }
    public string Unit { get; set; } = string.Empty;
    public DateOnly LastPurchaseDate { get; set; }
    public bool IsBest { get; set; }
    public int Deals { get; set; }
    public double? VolumeWeightedLanding { get; set; }
}

public class CatalogItemTradeSupplierPricesOut
{
    public Guid CatalogItemId { get; set; }
    public List<TradeSupplierPriceRow> Suppliers { get; set; } = new();
    public List<double> LastFiveLandingPrices { get; set; } = new();
    public double? AvgLandingFromTrade { get; set; }
}

// -- Insights --
public class CatalogItemInsightsOut
{
    public int LineCount { get; set; }
    public int EntryCount { get; set; }
    public double TotalProfit { get; set; }
    public double? AvgLanding { get; set; }
    public double? AvgSelling { get; set; }
    public DateOnly? LastEntryDate { get; set; }
    public double? ProfitMarginPct { get; set; }
}

public class CategoryInsightsOut
{
    public int ItemCount { get; set; }
    public int LinkedLineCount { get; set; }
    public double TotalProfit { get; set; }
    public string? TopItemName { get; set; }
    public double? TopItemProfit { get; set; }
    public string? WorstItemName { get; set; }
    public double? WorstItemProfit { get; set; }
}

// -- Lines --
public class CatalogItemLineRow
{
    public Guid EntryId { get; set; }
    public DateOnly EntryDate { get; set; }
    public double Qty { get; set; }
    public string Unit { get; set; } = string.Empty;
    public double LandingCost { get; set; }
    public double? SellingPrice { get; set; }
    public double? Profit { get; set; }
    public string? SupplierName { get; set; }
    public string? SupplierPhone { get; set; }
    public string? BrokerName { get; set; }
    public string? BrokerPhone { get; set; }
    public string? PurchaseHumanId { get; set; }
    public double? KgPerUnit { get; set; }
    public double? LandingCostPerKg { get; set; }
    public Dictionary<string, object>? UnitResolution { get; set; }
}

// -- Trade summary --
public class CategoryTradeItemRow
{
    public Guid CatalogItemId { get; set; }
    public string Name { get; set; } = string.Empty;
    public double PeriodLineTotal { get; set; }
    public double PeriodQtyBags { get; set; }
    public double PeriodWeightKg { get; set; }
    public double? LastPurchasePrice { get; set; }
    public double? LastSellingRate { get; set; }
    public string? LastSupplierName { get; set; }
    public string? LastBrokerName { get; set; }
    public string? LastTradeHumanId { get; set; }
}

public class CategoryTradeSummaryOut
{
    public int ItemCount { get; set; }
    public double TotalLineAmount { get; set; }
    public double TotalQtyBags { get; set; }
    public double TotalWeightKg { get; set; }
    public List<CategoryTradeItemRow> Items { get; set; } = new();
}

// -- Fuzzy check --
public class CatalogFuzzyCheckResponse
{
    public List<CatalogFuzzyHit> Hits { get; set; } = new();
}

public class CatalogFuzzyHit
{
    public Guid Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public double Score { get; set; }
}

// -- Duplicate clusters --
public class CatalogDuplicateClustersResponse
{
    public List<CatalogDuplicatePair> Pairs { get; set; } = new();
}

public class CatalogDuplicatePair
{
    public Guid IdA { get; set; }
    public string NameA { get; set; } = string.Empty;
    public Guid IdB { get; set; }
    public string NameB { get; set; } = string.Empty;
    public double Score { get; set; }
}

// -- Variants --
public class CatalogVariantOut
{
    public Guid Id { get; set; }
    public Guid CatalogItemId { get; set; }
    public string Name { get; set; } = string.Empty;
    public double? DefaultKgPerBag { get; set; }
}

public class CatalogVariantCreateRequest
{
    [StringLength(512)]
    public string Name { get; set; } = string.Empty;
    public double? DefaultKgPerBag { get; set; }
}

public class CatalogVariantUpdateRequest
{
    [StringLength(512)]
    public string? Name { get; set; }
    public double? DefaultKgPerBag { get; set; }
}

// -- Bulk --
public class BulkItemIdsIn
{
    public List<Guid> ItemIds { get; set; } = new();
}

public class BulkReorderIn
{
    public List<Guid> ItemIds { get; set; } = new();
    public double ReorderLevel { get; set; }
}
