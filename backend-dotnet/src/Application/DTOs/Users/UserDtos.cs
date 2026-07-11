namespace PurchaseAssistant.Application.DTOs.Users;

public record UserCreateIn(
    string FullName,
    string? Email,
    string Phone,
    string Role,
    string? Password = null,
    string? Notes = null,
    bool IsActive = true);

public record UserPatchIn(
    string? FullName = null,
    string? Email = null,
    string? Phone = null,
    string? Role = null,
    bool? IsActive = null,
    bool? IsBlocked = null,
    string? Notes = null);

public record UserBulkIn(
    List<Guid> UserIds,
    string Action,
    string? Role = null);

public record UserBulkOut(int Updated, List<string> Failed);

public record UserListOut(
    Guid Id, string? Name, string? Phone, string Email, string? Username,
    string Role, bool IsActive, bool IsBlocked,
    DateTime? LastLoginAt, DateTime? LastActiveAt,
    string? Notes, DateTime? CreatedAt);

public record UserProfileOut(
    Guid Id, string? Name, string? Phone, string Email, string? Username,
    string Role, bool IsActive, bool IsBlocked,
    DateTime? LastLoginAt, DateTime? LastActiveAt,
    string? Notes, DateTime? CreatedAt,
    string? LoginEmail);

public record UserCreateOut(UserListOut User, string? GeneratedPassword, string? LoginEmail);

public record ResetPasswordOut(string NewPassword, string? LoginEmail = null);

public record ActivityLogIn(string ActionType, Guid? ItemId = null, string? ItemName = null, Dictionary<string, object>? Details = null);

public record ActivityLogOut(Guid Id, string? UserName, string ActionType, Guid? ItemId, string? ItemName, Dictionary<string, object>? Details, DateTime CreatedAt);

public record PermissionsOut(string Role, Dictionary<string, bool> Permissions);

public record PermissionsPatchIn(Dictionary<string, bool> Permissions);

public record LedgerEntryOut(string Kind, DateTime At, string Title, string? Subtitle = null, Dictionary<string, object>? Details = null);

public record LedgerGroupedOut(List<LedgerEntryOut> Today, List<LedgerEntryOut> Yesterday, List<LedgerEntryOut> ThisWeek);

public record StockAdjustmentOut(Guid Id, Guid ItemId, string? ItemName, decimal OldQty, decimal NewQty, string AdjustmentType, string? Reason, DateTime UpdatedAt);

public record UserPurchaseBrief(Guid Id, string? HumanId, DateTime? PurchaseDate, string? Status, decimal? TotalAmount, string? SupplierName, int? ItemCount);

public record CreatedItemOut(Guid Id, string? Name, string? Barcode, string? Category, decimal? ReorderLevel, DateTime? UpdatedAt);
