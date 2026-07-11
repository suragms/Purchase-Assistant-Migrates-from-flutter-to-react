using System.ComponentModel.DataAnnotations.Schema;
using PurchaseAssistant.Domain.Common;

namespace PurchaseAssistant.Domain.Entities.Units;

[Table("item_learning_history")]
public class ItemLearningHistory : BaseEntity
{
    [Column("catalog_item_id")]
    public Guid CatalogItemId { get; set; }

    [Column("corrected_unit")]
    public string? CorrectedUnit { get; set; }

    [Column("corrected_package_type")]
    public string? CorrectedPackageType { get; set; }

    [Column("user_id")]
    public Guid? UserId { get; set; }
}
