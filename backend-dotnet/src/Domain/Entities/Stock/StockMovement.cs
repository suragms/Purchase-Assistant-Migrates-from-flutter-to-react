using System.ComponentModel.DataAnnotations.Schema;
using PurchaseAssistant.Domain.Common;

namespace PurchaseAssistant.Domain.Entities.Stock;

[Table("stock_movements")]
public class StockMovement : BaseEntity
{
    [Column("business_id")]
    public Guid BusinessId { get; set; }

    [Column("item_id")]
    public Guid ItemId { get; set; }

    [Column("from_location")]
    public string? FromLocation { get; set; }

    [Column("to_location")]
    public string? ToLocation { get; set; }

    [Column("qty")]
    public decimal? Qty { get; set; }

    [Column("unit")]
    public string? Unit { get; set; }

    [Column("unit_mismatch_flag")]
    public bool UnitMismatchFlag { get; set; } = false;

    [Column("moved_by")]
    public Guid? MovedBy { get; set; }

    [Column("notes")]
    public string? Notes { get; set; }
}
