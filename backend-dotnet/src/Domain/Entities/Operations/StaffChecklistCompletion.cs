using System.ComponentModel.DataAnnotations.Schema;
using PurchaseAssistant.Domain.Common;

namespace PurchaseAssistant.Domain.Entities.Operations;

[Table("staff_checklist_completions")]
public class StaffChecklistCompletion : BaseEntity
{
    [Column("checklist_id")]
    public Guid ChecklistId { get; set; }

    [Column("business_id")]
    public Guid BusinessId { get; set; }

    [Column("user_id")]
    public Guid UserId { get; set; }

    [Column("completed_at")]
    public DateTime? CompletedAt { get; set; }
}
