using System.ComponentModel.DataAnnotations.Schema;
using PurchaseAssistant.Domain.Common;

namespace PurchaseAssistant.Domain.Entities.Catalog;

[Table("catalog_item_default_brokers")]
public class CatalogItemDefaultBroker : BaseEntity
{
    [Column("business_id")]
    public Guid BusinessId { get; set; }

    [Column("catalog_item_id")]
    public Guid CatalogItemId { get; set; }

    [Column("broker_id")]
    public Guid BrokerId { get; set; }

    [Column("sort_order")]
    public int SortOrder { get; set; } = 0;
}
