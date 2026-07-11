using System.ComponentModel.DataAnnotations.Schema;
using PurchaseAssistant.Domain.Common;

namespace PurchaseAssistant.Domain.Entities.Units;

[Table("ocr_item_aliases")]
public class OcrItemAlias : BaseEntity
{
    [Column("business_id")]
    public Guid BusinessId { get; set; }

    [Column("catalog_item_id")]
    public Guid CatalogItemId { get; set; }

    [Column("alias_text")]
    public string? AliasText { get; set; }

    [Column("source")]
    public string? Source { get; set; }

    [Column("confidence")]
    public float? Confidence { get; set; }
}
