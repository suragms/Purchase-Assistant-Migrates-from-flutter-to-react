using System.ComponentModel.DataAnnotations.Schema;
using PurchaseAssistant.Domain.Common;

namespace PurchaseAssistant.Domain.Entities.Config;

[Table("business_goals")]
public class BusinessGoal : BaseEntity
{
    [Column("business_id")]
    public Guid BusinessId { get; set; }

    [Column("metric")]
    public string? Metric { get; set; }

    [Column("target_value")]
    public decimal? TargetValue { get; set; }

    [Column("period")]
    public string? Period { get; set; }
}
