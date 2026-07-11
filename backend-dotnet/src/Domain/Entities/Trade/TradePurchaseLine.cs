using System.ComponentModel.DataAnnotations.Schema;
using PurchaseAssistant.Domain.Common;

namespace PurchaseAssistant.Domain.Entities.Trade;

[Table("trade_purchase_lines")]
public class TradePurchaseLine : BaseEntity
{
    [Column("trade_purchase_id")]
    public Guid TradePurchaseId { get; set; }

    [Column("catalog_item_id")]
    public Guid? CatalogItemId { get; set; }

    [Column("item_name")]
    public string ItemName { get; set; } = string.Empty;

    [Column("qty")]
    public decimal Qty { get; set; }

    [Column("unit")]
    public string Unit { get; set; } = string.Empty;

    [Column("qty_in_stock_unit")]
    public decimal? QtyInStockUnit { get; set; }

    [Column("landing_cost")]
    public decimal LandingCost { get; set; }

    [Column("selling_rate")]
    public decimal? SellingRate { get; set; }

    [Column("selling_cost")]
    public decimal? SellingCost { get; set; }

    [Column("line_total")]
    public decimal? LineTotal { get; set; }

    [Column("profit")]
    public decimal? Profit { get; set; }

    [Column("discount_pct")]
    public decimal? DiscountPct { get; set; }

    [Column("tax_mode")]
    public string? TaxMode { get; set; }

    [Column("tax_percent")]
    public decimal? TaxPercent { get; set; }

    [Column("kg_per_unit")]
    public decimal? KgPerUnit { get; set; }

    [Column("total_weight")]
    public decimal? TotalWeight { get; set; }

    [Column("landing_cost_per_kg")]
    public decimal? LandingCostPerKg { get; set; }

    [Column("received_qty")]
    public decimal? ReceivedQty { get; set; }

    [Column("damaged_qty")]
    public decimal? DamagedQty { get; set; }

    [Column("return_qty")]
    public decimal? ReturnQty { get; set; }

    [Column("sort_order")]
    public int? SortOrder { get; set; }
}
