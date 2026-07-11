using System.Text.Json.Serialization;

namespace PurchaseAssistant.Application.DTOs;

// ── Auth route responses ──
public record UserProfileResponse(
    Guid Id,
    string Email,
    string Username,
    string? Name,
    bool IsSuperAdmin
);

public record UserProfilePatch(string? Name);

// ── Business brief ──
public record BusinessBriefResponse(
    Guid Id,
    string Name,
    string Role,
    Dictionary<string, bool> Permissions,
    string? BrandingTitle,
    string? BrandingLogoUrl,
    string? GstNumber,
    string? Address,
    string? Phone,
    string? ContactEmail
);

public record BusinessBrandingPatch(
    string? Name,
    string? BrandingTitle,
    string? BrandingLogoUrl,
    string? GstNumber,
    string? Address,
    string? Phone,
    string? ContactEmail
);

public record BootstrapWorkspaceResponse(
    Guid BusinessId,
    bool CreatedBusiness,
    bool Seeded,
    Dictionary<string, int>? SeedStats
);

public record SessionResponse(
    [property: JsonPropertyName("id")] Guid Id,
    [property: JsonPropertyName("email")] string Email,
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("primaryBusiness")] PrimaryBusinessResponse PrimaryBusiness
);

public record PrimaryBusinessResponse(
    [property: JsonPropertyName("id")] Guid Id,
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("role")] string Role,
    [property: JsonPropertyName("currency")] string Currency
);

// ── Users routes ──
public record UserCreateRequest(
    string FullName,
    string? Email,
    string Phone,
    string Role,
    string? Password,
    string? Notes,
    bool IsActive = true
);

public record UserPatchRequest(
    string? FullName,
    string? Email,
    string? Phone,
    string? Role,
    bool? IsActive,
    bool? IsBlocked,
    string? Notes
);

public record UserBulkActionRequest(
    List<Guid> UserIds,
    string Action,
    string? Role
);

public record UserBulkActionResponse(
    int Updated,
    List<string> Failed
);

public record TodayStatsResponse(
    int Scans,
    int StockUpdates,
    int ItemsCreated
);

public record UserListResponse(
    Guid Id,
    string? Name,
    string? Phone,
    string Email,
    string? Username,
    string Role,
    bool IsActive,
    bool IsBlocked,
    DateTimeOffset? LastLoginAt,
    DateTimeOffset? LastActiveAt,
    TodayStatsResponse TodayStats,
    string? WarehouseName,
    int ActivityCount7d,
    string? Notes,
    DateTimeOffset? CreatedAt
);

public record ProfileStatsResponse(
    int StockEditsTotal,
    int PurchasesTotal,
    int ScansTotal,
    int ItemsCreatedTotal
);

public record UserProfileDetailResponse(
    UserListResponse User,
    string? LoginEmail,
    int Purchases7d,
    int StockUpdates7d,
    ProfileStatsResponse? Stats
);

public record UserCreateResponse(
    UserListResponse User,
    string? GeneratedPassword,
    string? LoginEmail
);

public record UserResetPasswordResponse(
    string NewPassword,
    string? LoginEmail
);

public record UserCredentialsResponse(
    string Username,
    string LoginEmail,
    string? Phone,
    string Note
);

public record UserStockAdjustmentResponse(
    Guid Id,
    Guid ItemId,
    string? ItemName,
    double OldQty,
    double NewQty,
    string AdjustmentType,
    string? Reason,
    DateTimeOffset UpdatedAt
);

public record CreatedItemResponse(
    Guid Id,
    string? Name,
    string? Barcode,
    string? Category,
    double? ReorderLevel,
    DateTimeOffset? UpdatedAt
);

public record UserPurchaseBriefResponse(
    Guid Id,
    string? HumanId,
    DateTimeOffset? PurchaseDate,
    string? Status,
    double? TotalAmount,
    string? SupplierName,
    int? ItemCount
);

public record LedgerEntryResponse(
    string Kind,
    DateTimeOffset At,
    string Title,
    string? Subtitle,
    Dictionary<string, object>? Details
);

public record LedgerGroupedResponse(
    List<LedgerEntryResponse> Today,
    List<LedgerEntryResponse> Yesterday,
    List<LedgerEntryResponse> ThisWeek
);

public record PermissionsResponse(
    string Role,
    Dictionary<string, bool> Permissions
);

public record PermissionsPatchRequest(
    Dictionary<string, bool> Permissions
);

// ── Activity log ──
public record ActivityLogRequest(
    string ActionType,
    Guid? ItemId,
    string? ItemName,
    Dictionary<string, object>? Details
);

public record ActivityLogResponse(
    Guid Id,
    string? UserName,
    string ActionType,
    Guid? ItemId,
    string? ItemName,
    Dictionary<string, object>? Details,
    DateTimeOffset CreatedAt
);
