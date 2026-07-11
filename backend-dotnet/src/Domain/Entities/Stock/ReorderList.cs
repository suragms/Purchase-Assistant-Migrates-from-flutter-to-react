using System.ComponentModel.DataAnnotations.Schema;
using PurchaseAssistant.Domain.Common;

namespace PurchaseAssistant.Domain.Entities.Stock;

[Table("reorder_list")]
public class ReorderList : BaseEntity
{
    [Column("business_id")]
    public Guid BusinessId { get; set; }

    [Column("catalog_item_id")]
    public Guid CatalogItemId { get; set; }

    [Column("suggested_qty")]
    public decimal? SuggestedQty { get; set; }

    [Column("notes")]
    public string? Notes { get; set; }
}
