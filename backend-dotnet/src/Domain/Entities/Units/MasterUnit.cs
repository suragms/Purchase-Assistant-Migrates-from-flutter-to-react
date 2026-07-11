using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using PurchaseAssistant.Domain.Common;

namespace PurchaseAssistant.Domain.Entities.Units;

[Table("master_units")]
public class MasterUnit
{
    [Key]
    [Column("code")]
    [MaxLength(16)]
    public string Code { get; set; } = string.Empty;

    [Column("label_plural")]
    public string? LabelPlural { get; set; }

    [Column("category")]
    public string? Category { get; set; }

    [Column("base_unit")]
    public string? BaseUnit { get; set; }

    [Column("conversion_to_base")]
    public decimal? ConversionToBase { get; set; }

    [Column("created_at")]
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
}
