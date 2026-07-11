using System.ComponentModel.DataAnnotations.Schema;
using PurchaseAssistant.Domain.Common;

namespace PurchaseAssistant.Domain.Entities.Units;

[Table("unit_confidence_logs")]
public class UnitConfidenceLog : BaseEntity
{
    [Column("catalog_item_id")]
    public Guid CatalogItemId { get; set; }

    [Column("source")]
    public string? Source { get; set; }

    [Column("unit_code")]
    public string? UnitCode { get; set; }

    [Column("confidence_score")]
    public float? ConfidenceScore { get; set; }
}
