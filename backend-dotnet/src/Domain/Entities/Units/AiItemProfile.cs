using System.ComponentModel.DataAnnotations.Schema;
using PurchaseAssistant.Domain.Common;

namespace PurchaseAssistant.Domain.Entities.Units;

[Table("ai_item_profiles")]
public class AiItemProfile : BaseEntity
{
    [Column("catalog_item_id")]
    public Guid CatalogItemId { get; set; }

    [Column("profile_data")]
    public string? ProfileData { get; set; }

    [Column("generated_by")]
    public string? GeneratedBy { get; set; }
}
