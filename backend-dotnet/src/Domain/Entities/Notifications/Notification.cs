using System.ComponentModel.DataAnnotations.Schema;
using PurchaseAssistant.Domain.Common;

namespace PurchaseAssistant.Domain.Entities.Notifications;

[Table("notifications")]
public class Notification : BaseEntity
{
    [Column("business_id")]
    public Guid? BusinessId { get; set; }

    [Column("user_id")]
    public Guid? UserId { get; set; }

    [Column("kind")]
    public string? Kind { get; set; }

    [Column("title")]
    public string? Title { get; set; }

    [Column("body")]
    public string? Body { get; set; }

    [Column("priority")]
    public string? Priority { get; set; }

    [Column("category")]
    public string? Category { get; set; }

    [Column("action_route")]
    public string? ActionRoute { get; set; }

    [Column("dedupe_key")]
    public string? DedupeKey { get; set; }

    [Column("payload")]
    public string? Payload { get; set; }

    [Column("triggered_by_user_id")]
    public Guid? TriggeredByUserId { get; set; }

    [Column("related_item_id")]
    public Guid? RelatedItemId { get; set; }

    [Column("related_purchase_id")]
    public Guid? RelatedPurchaseId { get; set; }

    [Column("read_at")]
    public DateTime? ReadAt { get; set; }
}
