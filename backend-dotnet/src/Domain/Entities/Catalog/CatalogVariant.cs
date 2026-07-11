using System.ComponentModel.DataAnnotations.Schema;
using PurchaseAssistant.Domain.Common;

namespace PurchaseAssistant.Domain.Entities.Catalog;

[Table("catalog_variants")]
public class CatalogVariant : BaseEntity
{
    [Column("business_id")]
    public Guid BusinessId { get; set; }

    [Column("catalog_item_id")]
    public Guid CatalogItemId { get; set; }

    [Column("name")]
    public string Name { get; set; } = string.Empty;

    [Column("default_kg_per_bag")]
    public decimal? DefaultKgPerBag { get; set; }
}
