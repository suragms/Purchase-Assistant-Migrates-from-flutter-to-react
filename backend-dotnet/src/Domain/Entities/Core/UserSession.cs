using System.ComponentModel.DataAnnotations.Schema;
using PurchaseAssistant.Domain.Common;

namespace PurchaseAssistant.Domain.Entities.Core;

[Table("user_sessions")]
public class UserSession : BaseEntity
{
    [Column("user_id")]
    public Guid UserId { get; set; }

    [Column("business_id")]
    public Guid? BusinessId { get; set; }

    [Column("login_at")]
    public DateTime LoginAt { get; set; } = DateTime.UtcNow;

    [Column("logout_at")]
    public DateTime? LogoutAt { get; set; }

    [Column("device_info")]
    public string? DeviceInfo { get; set; }

    [Column("is_active")]
    public bool IsActive { get; set; } = true;
}
