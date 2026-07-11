using System.ComponentModel.DataAnnotations.Schema;
using PurchaseAssistant.Domain.Common;

namespace PurchaseAssistant.Domain.Entities.Activity;

[Table("staff_activity_log")]
public class StaffActivityLog : BaseEntity
{
    [Column("business_id")]
    public Guid BusinessId { get; set; }

    [Column("user_id")]
    public Guid UserId { get; set; }

    [Column("user_name")]
    public string? UserName { get; set; }

    [Column("action_type")]
    public string ActionType { get; set; } = string.Empty;

    [Column("item_id")]
    public Guid? ItemId { get; set; }

    [Column("item_name")]
    public string? ItemName { get; set; }

    [Column("details")]
    public string? Details { get; set; }
}
