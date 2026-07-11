namespace PurchaseAssistant.Application.DTOs.Me;

public record UserProfilePatch(string? Name = null);
public record BootstrapWorkspaceOut(Guid BusinessId, string Name, int ItemsCreated, int SuppliersCreated);

public record BusinessBrief(
    Guid Id, string Name, string? Title, string? LogoUrl,
    string Role, Dictionary<string, bool>? Permissions);

public record BusinessBrandingPatch(
    string? Name = null, string? Title = null, string? LogoUrl = null,
    string? GstNumber = null, string? Address = null,
    string? Phone = null, string? Email = null);
