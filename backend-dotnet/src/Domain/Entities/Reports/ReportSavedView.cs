using System.ComponentModel.DataAnnotations.Schema;
using PurchaseAssistant.Domain.Common;

namespace PurchaseAssistant.Domain.Entities.Reports;

[Table("report_saved_views")]
public class ReportSavedView : BaseEntity
{
    [Column("business_id")]
    public Guid BusinessId { get; set; }

    [Column("user_id")]
    public Guid UserId { get; set; }

    [Column("name")]
    public string? Name { get; set; }

    [Column("report_type")]
    public string? ReportType { get; set; }

    [Column("filters")]
    public string? Filters { get; set; }
}
