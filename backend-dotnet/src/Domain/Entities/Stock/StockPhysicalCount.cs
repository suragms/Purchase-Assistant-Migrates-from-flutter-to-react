using System.ComponentModel.DataAnnotations.Schema;
using PurchaseAssistant.Domain.Common;

namespace PurchaseAssistant.Domain.Entities.Stock;

[Table("stock_physical_counts")]
public class StockPhysicalCount : BaseEntity
{
    [Column("business_id")]
    public Guid BusinessId { get; set; }

    [Column("item_id")]
    public Guid ItemId { get; set; }

    [Column("counted_qty")]
    public decimal? CountedQty { get; set; }

    [Column("system_qty")]
    public decimal? SystemQty { get; set; }

    [Column("unit")]
    public string? Unit { get; set; }

    [Column("variance")]
    public decimal? Variance { get; set; }

    [Column("counted_by")]
    public Guid? CountedBy { get; set; }

    [Column("notes")]
    public string? Notes { get; set; }

    [Column("idempotency_key")]
    public string? IdempotencyKey { get; set; }

    [Column("is_verified")]
    public bool IsVerified { get; set; } = false;

    [Column("verified_by")]
    public Guid? VerifiedBy { get; set; }

    [Column("verified_at")]
    public DateTime? VerifiedAt { get; set; }
}
