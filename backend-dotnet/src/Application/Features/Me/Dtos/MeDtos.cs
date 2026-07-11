using System.ComponentModel.DataAnnotations;

namespace PurchaseAssistant.Application.Features.Me.Dtos;

public class UserProfileResponse
{
    public Guid Id { get; set; }
    public string Email { get; set; } = string.Empty;
    public string Username { get; set; } = string.Empty;
    public string? Name { get; set; }
    public bool IsSuperAdmin { get; set; }
}

public class UserProfilePatchRequest
{
    [StringLength(255)]
    public string? Name { get; set; }
}

public class BusinessBriefResponse
{
    public Guid Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public string Role { get; set; } = string.Empty;
    public Dictionary<string, bool> Permissions { get; set; } = new();
    public string? BrandingTitle { get; set; }
    public string? BrandingLogoUrl { get; set; }
    public string? GstNumber { get; set; }
    public string? Address { get; set; }
    public string? Phone { get; set; }
    public string? ContactEmail { get; set; }
}

public class BootstrapWorkspaceResponse
{
    public Guid BusinessId { get; set; }
    public bool CreatedBusiness { get; set; }
    public bool Seeded { get; set; }
    public Dictionary<string, int>? SeedStats { get; set; }
}

public class BusinessBrandingPatchRequest
{
    [StringLength(255)]
    public string? Name { get; set; }

    [StringLength(128)]
    public string? BrandingTitle { get; set; }

    [StringLength(512)]
    public string? BrandingLogoUrl { get; set; }

    [StringLength(20)]
    public string? GstNumber { get; set; }

    public string? Address { get; set; }

    [StringLength(32)]
    public string? Phone { get; set; }

    [StringLength(255)]
    public string? ContactEmail { get; set; }
}
