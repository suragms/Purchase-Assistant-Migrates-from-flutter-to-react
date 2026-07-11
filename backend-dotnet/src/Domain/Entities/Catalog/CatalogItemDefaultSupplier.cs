using System.ComponentModel.DataAnnotations.Schema;
using PurchaseAssistant.Domain.Common;

namespace PurchaseAssistant.Domain.Entities.Catalog;

[Table("catalog_item_default_suppliers")]
public class CatalogItemDefaultSupplier : BaseEntity
{
    [Column("business_id")]
    public Guid BusinessId { get; set; }

    [Column("catalog_item_id")]
    public Guid CatalogItemId { get; set; }

    [Column("supplier_id")]
    public Guid SupplierId { get; set; }

    [Column("sort_order")]
    public int SortOrder { get; set; } = 0;
}
