using System.ComponentModel.DataAnnotations.Schema;
using PurchaseAssistant.Domain.Common;

namespace PurchaseAssistant.Domain.Entities.Stock;

[Table("stock_dispute_cases")]
public class StockDisputeCase : BaseEntity
{
    [Column("business_id")]
    public Guid BusinessId { get; set; }

    [Column("item_id")]
    public Guid ItemId { get; set; }

    [Column("reported_by")]
    public Guid? ReportedBy { get; set; }

    [Column("expected_qty")]
    public decimal? ExpectedQty { get; set; }

    [Column("actual_qty")]
    public decimal? ActualQty { get; set; }

    [Column("reason")]
    public string? Reason { get; set; }

    [Column("status")]
    public string Status { get; set; } = "open";

    [Column("resolved_by")]
    public Guid? ResolvedBy { get; set; }

    [Column("resolved_at")]
    public DateTime? ResolvedAt { get; set; }

    [Column("resolution_notes")]
    public string? ResolutionNotes { get; set; }
}
