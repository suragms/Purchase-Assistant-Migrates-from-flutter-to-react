using System.ComponentModel.DataAnnotations.Schema;
using PurchaseAssistant.Domain.Common;

namespace PurchaseAssistant.Domain.Entities.Operations;

[Table("staff_checklist_templates")]
public class StaffChecklistTemplate : BaseEntity
{
    [Column("business_id")]
    public Guid BusinessId { get; set; }

    [Column("title")]
    public string? Title { get; set; }

    [Column("description")]
    public string? Description { get; set; }

    [Column("frequency")]
    public string? Frequency { get; set; }
}
