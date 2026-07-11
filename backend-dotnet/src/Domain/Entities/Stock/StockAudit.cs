using System.ComponentModel.DataAnnotations.Schema;
using PurchaseAssistant.Domain.Common;

namespace PurchaseAssistant.Domain.Entities.Stock;

[Table("stock_audits")]
public class StockAudit : BaseEntity
{
    [Column("business_id")]
    public Guid BusinessId { get; set; }

    [Column("title")]
    public string? Title { get; set; }

    [Column("status")]
    public string Status { get; set; } = "in_progress";

    [Column("notes")]
    public string? Notes { get; set; }

    [Column("created_by")]
    public Guid? CreatedBy { get; set; }

    [Column("completed_by")]
    public Guid? CompletedBy { get; set; }

    [Column("completed_at")]
    public DateTime? CompletedAt { get; set; }
}
