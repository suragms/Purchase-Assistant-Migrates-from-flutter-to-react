using System.ComponentModel.DataAnnotations.Schema;
using PurchaseAssistant.Domain.Common;

namespace PurchaseAssistant.Domain.Entities.Trade;

[Table("purchase_lifecycle_events")]
public class PurchaseLifecycleEvent : BaseEntity
{
    [Column("trade_purchase_id")]
    public Guid TradePurchaseId { get; set; }

    [Column("from_status")]
    public string? FromStatus { get; set; }

    [Column("to_status")]
    public string? ToStatus { get; set; }

    [Column("actor_id")]
    public Guid? ActorId { get; set; }

    [Column("notes")]
    public string? Notes { get; set; }

    [Column("metadata")]
    public string? Metadata { get; set; }
}
