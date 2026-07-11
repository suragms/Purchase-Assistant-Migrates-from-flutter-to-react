using System.ComponentModel.DataAnnotations.Schema;
using PurchaseAssistant.Domain.Common;

namespace PurchaseAssistant.Domain.Entities.Units;

[Table("item_packaging_profiles")]
public class ItemPackagingProfile : BaseEntity
{
    [Column("catalog_item_id")]
    public Guid CatalogItemId { get; set; }

    [Column("profile_type")]
    public string? ProfileType { get; set; }

    [Column("display_unit")]
    public string? DisplayUnit { get; set; }

    [Column("stock_unit")]
    public string? StockUnit { get; set; }

    [Column("package_size")]
    public decimal? PackageSize { get; set; }

    [Column("package_measurement")]
    public string? PackageMeasurement { get; set; }
}
