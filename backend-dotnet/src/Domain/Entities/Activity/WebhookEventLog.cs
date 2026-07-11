using System.ComponentModel.DataAnnotations.Schema;
using PurchaseAssistant.Domain.Common;

namespace PurchaseAssistant.Domain.Entities.Activity;

[Table("webhook_event_logs")]
public class WebhookEventLog : BaseEntity
{
    [Column("event_type")]
    public string? EventType { get; set; }

    [Column("payload")]
    public string? Payload { get; set; }

    [Column("status")]
    public string? Status { get; set; }
}
