namespace PurchaseAssistant.Application.DTOs.Users;

public class UserProfileDto
{
    public Guid Id { get; set; }
    public string Email { get; set; } = string.Empty;
    public string Username { get; set; } = string.Empty;
    public string? Name { get; set; }
    public bool IsSuperAdmin { get; set; }
}

public class UserCreateRequest
{
    public string FullName { get; set; } = string.Empty;
    public string? Email { get; set; }
    public string Phone { get; set; } = string.Empty;
    public string Role { get; set; } = string.Empty;
    public string? Password { get; set; }
    public string? Notes { get; set; }
    public bool IsActive { get; set; } = true;
}

public class UserPatchRequest
{
    public string? FullName { get; set; }
    public string? Email { get; set; }
    public string? Phone { get; set; }
    public string? Role { get; set; }
    public bool? IsActive { get; set; }
    public bool? IsBlocked { get; set; }
    public string? Notes { get; set; }
}

public class UserListDto
{
    public Guid Id { get; set; }
    public string? Name { get; set; }
    public string? Phone { get; set; }
    public string Email { get; set; } = string.Empty;
    public string Role { get; set; } = string.Empty;
    public bool IsActive { get; set; }
    public bool IsBlocked { get; set; }
    public DateTimeOffset? LastLoginAt { get; set; }
    public string? Notes { get; set; }
    public DateTimeOffset? CreatedAt { get; set; }
}

public class UserBulkRequest
{
    public List<Guid> UserIds { get; set; } = new();
    public string Action { get; set; } = string.Empty;
    public string? Role { get; set; }
}

public class UserBulkResponse
{
    public int Updated { get; set; }
    public List<string> Failed { get; set; } = new();
}

public class UserPermissionsDto
{
    public string Role { get; set; } = string.Empty;
    public Dictionary<string, bool> Permissions { get; set; } = new();
}

public class PermissionsPatchRequest
{
    public Dictionary<string, bool> Permissions { get; set; } = new();
}

public class CreatedItemDto
{
    public Guid Id { get; set; }
    public string? Name { get; set; }
    public string? Barcode { get; set; }
    public string? Category { get; set; }
    public double? ReorderLevel { get; set; }
    public DateTimeOffset? UpdatedAt { get; set; }
}

public class StockAdjustmentDto
{
    public Guid Id { get; set; }
    public Guid ItemId { get; set; }
    public string? ItemName { get; set; }
    public double OldQty { get; set; }
    public double NewQty { get; set; }
    public string AdjustmentType { get; set; } = string.Empty;
    public string? Reason { get; set; }
    public DateTimeOffset UpdatedAt { get; set; }
}

public class LedgerEntryDto
{
    public string Kind { get; set; } = string.Empty;
    public DateTimeOffset At { get; set; }
    public string Title { get; set; } = string.Empty;
    public string? Subtitle { get; set; }
    public Dictionary<string, object>? Details { get; set; }
}

public class ActivityLogEntryDto
{
    public Guid Id { get; set; }
    public string? UserName { get; set; }
    public string ActionType { get; set; } = string.Empty;
    public Guid? ItemId { get; set; }
    public string? ItemName { get; set; }
    public Dictionary<string, object>? Details { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
}
