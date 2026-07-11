using System.ComponentModel.DataAnnotations.Schema;
using PurchaseAssistant.Domain.Common;

namespace PurchaseAssistant.Domain.Entities.Operations;

[Table("daily_usage_logs")]
public class DailyUsageLog : BaseEntity
{
    [Column("business_id")]
    public Guid BusinessId { get; set; }

    [Column("item_id")]
    public Guid ItemId { get; set; }

    [Column("qty_used")]
    public decimal? QtyUsed { get; set; }

    [Column("unit")]
    public string? Unit { get; set; }

    [Column("usage_date")]
    public DateOnly? UsageDate { get; set; }

    [Column("logged_by")]
    public Guid? LoggedBy { get; set; }

    [Column("notes")]
    public string? Notes { get; set; }
}
