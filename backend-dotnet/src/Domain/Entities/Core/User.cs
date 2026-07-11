using System.ComponentModel.DataAnnotations.Schema;
using PurchaseAssistant.Domain.Common;

namespace PurchaseAssistant.Domain.Entities.Core;

[Table("users")]
public class User : BaseEntity
{
    [Column("email")]
    public string Email { get; set; } = string.Empty;

    [Column("username")]
    public string Username { get; set; } = string.Empty;

    [Column("password_hash")]
    public string? PasswordHash { get; set; }

    [Column("name")]
    public string? Name { get; set; }

    [Column("phone")]
    public string? Phone { get; set; }

    [Column("google_sub")]
    public string? GoogleSub { get; set; }

    [Column("ai_monthly_token_budget")]
    public int? AiMonthlyTokenBudget { get; set; } = 100000;

    [Column("ai_tokens_used_month")]
    public int? AiTokensUsedMonth { get; set; } = 0;

    [Column("is_active")]
    public bool IsActive { get; set; } = true;

    [Column("is_super_admin")]
    public bool IsSuperAdmin { get; set; } = false;

    [Column("is_blocked")]
    public bool IsBlocked { get; set; } = false;

    [Column("notes")]
    public string? Notes { get; set; }

    [Column("device_info")]
    public string? DeviceInfo { get; set; }

    [Column("token_version")]
    public int TokenVersion { get; set; } = 0;

    [Column("created_by")]
    public Guid? CreatedBy { get; set; }

    [Column("last_login_at")]
    public DateTime? LastLoginAt { get; set; }

    [Column("last_active_at")]
    public DateTime? LastActiveAt { get; set; }

    [Column("deleted_at")]
    public DateTime? DeletedAt { get; set; }
}
