using System.ComponentModel.DataAnnotations.Schema;
using PurchaseAssistant.Domain.Common;

namespace PurchaseAssistant.Domain.Entities.Units;

[Table("smart_unit_rules")]
public class SmartUnitRule : BaseEntity
{
    [Column("keyword")]
    public string? Keyword { get; set; }

    [Column("unit_code")]
    public string? UnitCode { get; set; }

    [Column("package_type")]
    public string? PackageType { get; set; }

    [Column("priority")]
    public int? Priority { get; set; }

    [Column("is_active")]
    public bool? IsActive { get; set; }
}
