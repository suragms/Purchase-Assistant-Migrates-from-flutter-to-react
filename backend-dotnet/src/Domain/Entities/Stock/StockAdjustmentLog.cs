using System.ComponentModel.DataAnnotations.Schema;
using PurchaseAssistant.Domain.Common;

namespace PurchaseAssistant.Domain.Entities.Stock;

[Table("stock_adjustment_log")]
public class StockAdjustmentLog : BaseEntity
{
    [Column("business_id")]
    public Guid BusinessId { get; set; }

    [Column("item_id")]
    public Guid ItemId { get; set; }

    [Column("old_qty")]
    public decimal? OldQty { get; set; }

    [Column("new_qty")]
    public decimal? NewQty { get; set; }

    [Column("adjustment_type")]
    public string? AdjustmentType { get; set; }

    [Column("reason")]
    public string? Reason { get; set; }

    [Column("updated_by")]
    public Guid? UpdatedBy { get; set; }

    [Column("updated_at")]
    public DateTime? UpdatedAt { get; set; }
}
