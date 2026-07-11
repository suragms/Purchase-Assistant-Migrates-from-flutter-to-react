using System.ComponentModel.DataAnnotations.Schema;
using PurchaseAssistant.Domain.Common;

namespace PurchaseAssistant.Domain.Entities.Catalog;

[Table("catalog_items")]
public class CatalogItem : BaseEntity
{
    [Column("business_id")]
    public Guid BusinessId { get; set; }

    [Column("category_id")]
    public Guid CategoryId { get; set; }

    [Column("type_id")]
    public Guid? TypeId { get; set; }

    [Column("name")]
    public string Name { get; set; } = string.Empty;

    [Column("normalized_name")]
    public string? NormalizedName { get; set; }

    [Column("default_unit")]
    public string? DefaultUnit { get; set; }

    [Column("default_purchase_unit")]
    public string? DefaultPurchaseUnit { get; set; }

    [Column("default_sale_unit")]
    public string? DefaultSaleUnit { get; set; }

    [Column("selling_unit")]
    public string? SellingUnit { get; set; }

    [Column("stock_unit")]
    public string? StockUnit { get; set; }

    [Column("display_unit")]
    public string? DisplayUnit { get; set; }

    [Column("package_type")]
    public string? PackageType { get; set; }

    [Column("package_size")]
    public decimal? PackageSize { get; set; }

    [Column("package_measurement")]
    public string? PackageMeasurement { get; set; }

    [Column("package_volume")]
    public decimal? PackageVolume { get; set; }

    [Column("package_weight")]
    public decimal? PackageWeight { get; set; }

    [Column("conversion_factor")]
    public decimal? ConversionFactor { get; set; }

    [Column("default_kg_per_bag")]
    public decimal? DefaultKgPerBag { get; set; }

    [Column("default_items_per_box")]
    public decimal? DefaultItemsPerBox { get; set; }

    [Column("default_weight_per_tin")]
    public decimal? DefaultWeightPerTin { get; set; }

    [Column("hsn_code")]
    public string? HsnCode { get; set; }

    [Column("item_code")]
    public string? ItemCode { get; set; }

    [Column("barcode")]
    public string? Barcode { get; set; }

    [Column("public_token")]
    public string? PublicToken { get; set; }

    [Column("tax_percent")]
    public decimal? TaxPercent { get; set; }

    [Column("default_landing_cost")]
    public decimal? DefaultLandingCost { get; set; }

    [Column("default_selling_cost")]
    public decimal? DefaultSellingCost { get; set; }

    [Column("reorder_level")]
    public decimal ReorderLevel { get; set; } = 0;

    [Column("current_stock")]
    public decimal CurrentStock { get; set; } = 0;

    [Column("opening_stock_qty")]
    public decimal? OpeningStockQty { get; set; }

    [Column("opening_stock_set_at")]
    public DateTime? OpeningStockSetAt { get; set; }

    [Column("opening_stock_set_by")]
    public string? OpeningStockSetBy { get; set; }

    [Column("opening_stock_locked")]
    public bool OpeningStockLocked { get; set; } = false;

    [Column("rack_location")]
    public string? RackLocation { get; set; }

    [Column("stock_version")]
    public int StockVersion { get; set; } = 0;

    [Column("auto_detect_enabled")]
    public bool AutoDetectEnabled { get; set; } = true;

    [Column("validation_status")]
    public string? ValidationStatus { get; set; }

    [Column("ai_detected_unit")]
    public string? AiDetectedUnit { get; set; }

    [Column("smart_classification")]
    public string? SmartClassification { get; set; }

    [Column("unit_confidence")]
    public decimal? UnitConfidence { get; set; }

    [Column("packaging_confidence")]
    public decimal? PackagingConfidence { get; set; }

    [Column("is_loose_item")]
    public bool? IsLooseItem { get; set; }

    [Column("is_packaged_item")]
    public bool? IsPackagedItem { get; set; }

    [Column("ml_profile")]
    public string? MlProfile { get; set; }

    [Column("last_purchase_price")]
    public decimal? LastPurchasePrice { get; set; }

    [Column("last_selling_rate")]
    public decimal? LastSellingRate { get; set; }

    [Column("last_supplier_id")]
    public Guid? LastSupplierId { get; set; }

    [Column("last_broker_id")]
    public Guid? LastBrokerId { get; set; }

    [Column("last_trade_purchase_id")]
    public Guid? LastTradePurchaseId { get; set; }

    [Column("last_line_qty")]
    public decimal? LastLineQty { get; set; }

    [Column("last_line_unit")]
    public string? LastLineUnit { get; set; }

    [Column("last_line_weight_kg")]
    public decimal? LastLineWeightKg { get; set; }

    [Column("last_purchase_at")]
    public DateTime? LastPurchaseAt { get; set; }

    [Column("eviction_days")]
    public int? EvictionDays { get; set; }

    [Column("last_stock_updated_at")]
    public DateTime? LastStockUpdatedAt { get; set; }

    [Column("last_stock_updated_by")]
    public string? LastStockUpdatedBy { get; set; }

    [Column("created_by_user_id")]
    public Guid? CreatedByUserId { get; set; }

    [Column("updated_by_user_id")]
    public Guid? UpdatedByUserId { get; set; }

    [Column("deleted_at")]
    public DateTime? DeletedAt { get; set; }

    [Column("archived_at")]
    public DateTime? ArchivedAt { get; set; }
}
