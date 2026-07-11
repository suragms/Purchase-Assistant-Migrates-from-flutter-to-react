using System.ComponentModel.DataAnnotations.Schema;
using PurchaseAssistant.Domain.Common;

namespace PurchaseAssistant.Domain.Entities.Trade;

[Table("trade_purchase_drafts")]
public class TradePurchaseDraft : BaseEntity
{
    [Column("business_id")]
    public Guid BusinessId { get; set; }

    [Column("user_id")]
    public Guid UserId { get; set; }

    [Column("step")]
    public string? Step { get; set; }

    [Column("payload")]
    public string? Payload { get; set; }
}
