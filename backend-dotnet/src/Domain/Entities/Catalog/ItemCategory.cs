using System.ComponentModel.DataAnnotations.Schema;
using PurchaseAssistant.Domain.Common;

namespace PurchaseAssistant.Domain.Entities.Catalog;

[Table("item_categories")]
public class ItemCategory : BaseEntity
{
    [Column("business_id")]
    public Guid BusinessId { get; set; }

    [Column("name")]
    public string Name { get; set; } = string.Empty;
}
