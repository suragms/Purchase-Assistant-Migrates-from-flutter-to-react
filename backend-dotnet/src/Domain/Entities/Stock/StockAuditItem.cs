using System.ComponentModel.DataAnnotations.Schema;
using PurchaseAssistant.Domain.Common;

namespace PurchaseAssistant.Domain.Entities.Stock;

[Table("stock_audit_items")]
public class StockAuditItem : BaseEntity
{
    [Column("stock_audit_id")]
    public Guid StockAuditId { get; set; }

    [Column("catalog_item_id")]
    public Guid CatalogItemId { get; set; }

    [Column("expected_qty")]
    public decimal? ExpectedQty { get; set; }

    [Column("actual_qty")]
    public decimal? ActualQty { get; set; }

    [Column("variance")]
    public decimal? Variance { get; set; }

    [Column("notes")]
    public string? Notes { get; set; }

    [Column("counted_at")]
    public DateTime? CountedAt { get; set; }
}
