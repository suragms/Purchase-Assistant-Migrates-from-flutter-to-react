using System.ComponentModel.DataAnnotations.Schema;
using PurchaseAssistant.Domain.Common;

namespace PurchaseAssistant.Domain.Entities.Activity;

[Table("api_usage_logs")]
public class ApiUsageLog : BaseEntity
{
    [Column("business_id")]
    public Guid? BusinessId { get; set; }

    [Column("user_id")]
    public Guid? UserId { get; set; }

    [Column("endpoint")]
    public string? Endpoint { get; set; }

    [Column("method")]
    public string? Method { get; set; }

    [Column("status_code")]
    public int? StatusCode { get; set; }

    [Column("response_ms")]
    public int? ResponseMs { get; set; }
}
