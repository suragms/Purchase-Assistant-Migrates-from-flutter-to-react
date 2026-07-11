using System.ComponentModel.DataAnnotations.Schema;
using PurchaseAssistant.Domain.Common;

namespace PurchaseAssistant.Domain.Entities.Operations;

[Table("staff_purchase_logs")]
public class StaffPurchaseLog : BaseEntity
{
    [Column("business_id")]
    public Guid BusinessId { get; set; }

    [Column("user_id")]
    public Guid UserId { get; set; }

    [Column("item_name")]
    public string? ItemName { get; set; }

    [Column("qty")]
    public decimal? Qty { get; set; }

    [Column("unit")]
    public string? Unit { get; set; }

    [Column("amount")]
    public decimal? Amount { get; set; }

    [Column("notes")]
    public string? Notes { get; set; }

    [Column("purchase_date")]
    public DateOnly? PurchaseDate { get; set; }
}
