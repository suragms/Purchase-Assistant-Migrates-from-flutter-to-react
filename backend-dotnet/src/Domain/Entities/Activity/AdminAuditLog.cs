using System.ComponentModel.DataAnnotations.Schema;
using PurchaseAssistant.Domain.Common;

namespace PurchaseAssistant.Domain.Entities.Activity;

[Table("admin_audit_logs")]
public class AdminAuditLog : BaseEntity
{
    [Column("admin_id")]
    public Guid AdminId { get; set; }

    [Column("action")]
    public string? Action { get; set; }

    [Column("target_type")]
    public string? TargetType { get; set; }

    [Column("target_id")]
    public Guid? TargetId { get; set; }

    [Column("details")]
    public string? Details { get; set; }
}
