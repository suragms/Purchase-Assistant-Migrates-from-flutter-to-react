using System.ComponentModel.DataAnnotations.Schema;
using PurchaseAssistant.Domain.Common;

namespace PurchaseAssistant.Domain.Entities.Catalog;

[Table("category_types")]
public class CategoryType : BaseEntity
{
    [Column("category_id")]
    public Guid CategoryId { get; set; }

    [Column("name")]
    public string Name { get; set; } = string.Empty;
}
