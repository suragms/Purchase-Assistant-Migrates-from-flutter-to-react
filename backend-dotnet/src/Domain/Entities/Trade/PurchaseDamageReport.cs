using System.ComponentModel.DataAnnotations.Schema;
using PurchaseAssistant.Domain.Common;

namespace PurchaseAssistant.Domain.Entities.Trade;

[Table("purchase_damage_reports")]
public class PurchaseDamageReport : BaseEntity
{
    [Column("business_id")]
    public Guid BusinessId { get; set; }

    [Column("trade_purchase_id")]
    public Guid? TradePurchaseId { get; set; }

    [Column("catalog_item_id")]
    public Guid? CatalogItemId { get; set; }

    [Column("reported_by")]
    public Guid? ReportedBy { get; set; }

    [Column("item_name")]
    public string? ItemName { get; set; }

    [Column("qty_damaged")]
    public decimal? QtyDamaged { get; set; }

    [Column("unit")]
    public string? Unit { get; set; }

    [Column("damage_type")]
    public string? DamageType { get; set; }

    [Column("status")]
    public string Status { get; set; } = "pending";

    [Column("reason")]
    public string? Reason { get; set; }

    [Column("photo_url")]
    public string? PhotoUrl { get; set; }

    [Column("notes")]
    public string? Notes { get; set; }

    [Column("resolution_notes")]
    public string? ResolutionNotes { get; set; }

    [Column("damage_items_in_batch")]
    public string? DamageItemsInBatch { get; set; }
}
