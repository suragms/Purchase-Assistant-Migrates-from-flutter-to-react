using System.ComponentModel.DataAnnotations.Schema;
using PurchaseAssistant.Domain.Common;

namespace PurchaseAssistant.Domain.Entities.Catalog;

[Table("supplier_item_defaults")]
public class SupplierItemDefault : BaseEntity
{
    [Column("business_id")]
    public Guid BusinessId { get; set; }

    [Column("catalog_item_id")]
    public Guid CatalogItemId { get; set; }

    [Column("supplier_id")]
    public Guid SupplierId { get; set; }

    [Column("last_price")]
    public decimal? LastPrice { get; set; }

    [Column("last_discount")]
    public decimal? LastDiscount { get; set; }

    [Column("last_payment_days")]
    public int? LastPaymentDays { get; set; }

    [Column("purchase_count")]
    public int PurchaseCount { get; set; } = 0;
}
