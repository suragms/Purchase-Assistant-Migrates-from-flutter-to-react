using System.ComponentModel.DataAnnotations.Schema;
using PurchaseAssistant.Domain.Common;

namespace PurchaseAssistant.Domain.Entities.Core;

[Table("memberships")]
public class Membership : BaseEntity
{
    [Column("user_id")]
    public Guid UserId { get; set; }

    [Column("business_id")]
    public Guid BusinessId { get; set; }

    [Column("role")]
    public string Role { get; set; } = string.Empty;

    [Column("permissions_json")]
    public string? PermissionsJson { get; set; }
}
