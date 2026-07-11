using System.ComponentModel.DataAnnotations.Schema;
using PurchaseAssistant.Domain.Common;

namespace PurchaseAssistant.Domain.Entities.Contacts;

[Table("broker_supplier_m2m")]
public class BrokerSupplierM2M : BaseEntity
{
    [Column("broker_id")]
    public Guid BrokerId { get; set; }

    [Column("supplier_id")]
    public Guid SupplierId { get; set; }
}
