using System.ComponentModel.DataAnnotations;

namespace PurchaseAssistant.Application.Features.Users.Dtos;

public class UserCreateRequest
{
    [Required, StringLength(255, MinimumLength = 1)]
    public string FullName { get; set; } = string.Empty;

    [StringLength(320, MinimumLength = 5)]
    public string? Email { get; set; }

    [Required, StringLength(32, MinimumLength = 6)]
    public string Phone { get; set; } = string.Empty;

    [Required, RegularExpression(@"^(admin|manager|staff)$")]
    public string Role { get; set; } = "staff";

    [StringLength(128)]
    public string? Password { get; set; }

    [StringLength(2000)]
    public string? Notes { get; set; }

    public bool IsActive { get; set; } = true;
}

public class UserPatchRequest
{
    [StringLength(255)]
    public string? FullName { get; set; }

    [StringLength(320)]
    public string? Email { get; set; }

    [StringLength(32)]
    public string? Phone { get; set; }

    [RegularExpression(@"^(admin|manager|staff|owner)$")]
    public string? Role { get; set; }

    public bool? IsActive { get; set; }

    public bool? IsBlocked { get; set; }

    [StringLength(2000)]
    public string? Notes { get; set; }
}

public class TodayStatsDto
{
    public int Scans { get; set; }
    public int StockUpdates { get; set; }
    public int ItemsCreated { get; set; }
}

public class UserListDto
{
    public Guid Id { get; set; }
    public string? Name { get; set; }
    public string? Phone { get; set; }
    public string Email { get; set; } = string.Empty;
    public string? Username { get; set; }
    public string Role { get; set; } = string.Empty;
    public bool IsActive { get; set; }
    public bool IsBlocked { get; set; }
    public DateTime? LastLoginAt { get; set; }
    public DateTime? LastActiveAt { get; set; }
    public TodayStatsDto TodayStats { get; set; } = new();
    public string? WarehouseName { get; set; }
    public int ActivityCount7D { get; set; }
    public string? Notes { get; set; }
    public DateTime? CreatedAt { get; set; }
}

public class ProfileStatsDto
{
    public int StockEditsTotal { get; set; }
    public int PurchasesTotal { get; set; }
    public int ScansTotal { get; set; }
    public int ItemsCreatedTotal { get; set; }
}

public class UserProfileDto : UserListDto
{
    public string? LoginEmail { get; set; }
    public int Purchases7D { get; set; }
    public int StockUpdates7D { get; set; }
    public ProfileStatsDto? Stats { get; set; }
}

public class UserCreateResponseDto
{
    public UserListDto User { get; set; } = new();
    public string? GeneratedPassword { get; set; }
    public string? LoginEmail { get; set; }
}

public class ResetPasswordResponseDto
{
    public string NewPassword { get; set; } = string.Empty;
    public string? LoginEmail { get; set; }
}

public class UserBulkRequest
{
    [Required, MinLength(1), MaxLength(100)]
    public List<Guid> UserIds { get; set; } = new();

    [Required, RegularExpression(@"^(activate|deactivate|block|unblock|delete|set_role)$")]
    public string Action { get; set; } = string.Empty;

    [RegularExpression(@"^(admin|manager|staff)$")]
    public string? Role { get; set; }
}

public class UserBulkResponseDto
{
    public int Updated { get; set; }
    public List<string> Failed { get; set; } = new();
}

public class ActivityLogRequest
{
    [Required]
    public string ActionType { get; set; } = string.Empty;

    public Guid? ItemId { get; set; }

    public string? ItemName { get; set; }

    public Dictionary<string, object>? Details { get; set; }
}

public class ActivityLogDto
{
    public Guid Id { get; set; }
    public string? UserName { get; set; }
    public string ActionType { get; set; } = string.Empty;
    public Guid? ItemId { get; set; }
    public string? ItemName { get; set; }
    public Dictionary<string, object>? Details { get; set; }
    public DateTime CreatedAt { get; set; }
}

public class StockAdjustmentDto
{
    public Guid Id { get; set; }
    public Guid ItemId { get; set; }
    public string? ItemName { get; set; }
    public decimal OldQty { get; set; }
    public decimal NewQty { get; set; }
    public string AdjustmentType { get; set; } = string.Empty;
    public string? Reason { get; set; }
    public DateTime UpdatedAt { get; set; }
}

public class UserPurchaseBriefDto
{
    public Guid Id { get; set; }
    public string? HumanId { get; set; }
    public DateTime? PurchaseDate { get; set; }
    public string? Status { get; set; }
    public decimal? TotalAmount { get; set; }
    public string? SupplierName { get; set; }
    public int? ItemCount { get; set; }
}

public class CreatedItemDto
{
    public Guid Id { get; set; }
    public string? Name { get; set; }
    public string? Barcode { get; set; }
    public string? Category { get; set; }
    public decimal? ReorderLevel { get; set; }
    public DateTime? UpdatedAt { get; set; }
}

public class LedgerEntryDto
{
    public string Kind { get; set; } = string.Empty;
    public DateTime At { get; set; }
    public string Title { get; set; } = string.Empty;
    public string? Subtitle { get; set; }
    public Dictionary<string, object>? Details { get; set; }
}

public class LedgerGroupedDto
{
    public List<LedgerEntryDto> Today { get; set; } = new();
    public List<LedgerEntryDto> Yesterday { get; set; } = new();
    public List<LedgerEntryDto> ThisWeek { get; set; } = new();
}

public class PermissionsDto
{
    public string Role { get; set; } = string.Empty;
    public Dictionary<string, bool> Permissions { get; set; } = new();
}

public class PermissionsPatchRequest
{
    public Dictionary<string, bool> Permissions { get; set; } = new();
}

public class CredentialsResponseDto
{
    public string Username { get; set; } = string.Empty;
    public string LoginEmail { get; set; } = string.Empty;
    public string? Phone { get; set; }
    public string Note { get; set; } = "Passwords cannot be retrieved. Use reset-password to issue a new one.";
}
