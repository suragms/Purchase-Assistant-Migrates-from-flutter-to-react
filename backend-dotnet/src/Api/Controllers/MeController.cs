using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using PurchaseAssistant.Application.Features.Me.Dtos;
using PurchaseAssistant.Domain.Entities.Core;
using PurchaseAssistant.Infrastructure.Data;

namespace PurchaseAssistant.Api.Controllers;

[ApiController]
[Authorize]
[Route("v1/me")]
public class MeController : ControllerBase
{
    private readonly PurchaseAssistantDbContext _db;
    private readonly IConfiguration _config;

    public MeController(PurchaseAssistantDbContext db, IConfiguration config)
    {
        _db = db;
        _config = config;
    }

    [HttpGet]
    public async Task<IActionResult> GetSession()
    {
        var user = await GetCurrentUser();

        var membership = await _db.Memberships
            .Where(m => m.UserId == user.Id)
            .Join(_db.Businesses,
                m => m.BusinessId,
                b => b.Id,
                (m, b) => new { Membership = m, Business = b })
            .FirstOrDefaultAsync();

        if (membership == null)
        {
            return BadRequest(new { detail = "User has no active workspace membership" });
        }

        return Ok(new
        {
            id = user.Id,
            email = user.Email,
            name = user.Name ?? user.Username,
            primaryBusiness = new
            {
                id = membership.Business.Id,
                name = membership.Business.Name,
                role = membership.Membership.Role,
                currency = membership.Business.DefaultCurrency
            }
        });
    }

    [HttpGet("profile")]
    public async Task<IActionResult> GetProfile()
    {
        var user = await GetCurrentUser();
        return Ok(new UserProfileResponse
        {
            Id = user.Id,
            Email = user.Email,
            Username = user.Username,
            Name = user.Name,
            IsSuperAdmin = user.IsSuperAdmin,
        });
    }

    [HttpPatch("profile")]
    public async Task<IActionResult> UpdateProfile([FromBody] UserProfilePatchRequest body)
    {
        var user = await GetCurrentUser();

        if (body.Name != null)
        {
            var t = body.Name.Trim();
            user.Name = string.IsNullOrEmpty(t) ? null : t;
        }

        await _db.SaveChangesAsync();

        return Ok(new UserProfileResponse
        {
            Id = user.Id,
            Email = user.Email,
            Username = user.Username,
            Name = user.Name,
            IsSuperAdmin = user.IsSuperAdmin,
        });
    }

    [HttpPost("bootstrap-workspace")]
    public async Task<IActionResult> BootstrapWorkspace()
    {
        var user = await GetCurrentUser();

        var existingBiz = await _db.Memberships
            .Where(m => m.UserId == user.Id)
            .Select(m => m.BusinessId)
            .FirstOrDefaultAsync();

        if (existingBiz != Guid.Empty)
        {
            return Ok(new BootstrapWorkspaceResponse
            {
                BusinessId = existingBiz,
                CreatedBusiness = false,
                Seeded = false,
            });
        }

        var biz = new Business { Name = "Harisree workspace" };
        _db.Businesses.Add(biz);
        await _db.SaveChangesAsync();

        _db.Memberships.Add(new Membership
        {
            UserId = user.Id,
            BusinessId = biz.Id,
            Role = "owner",
        });
        await _db.SaveChangesAsync();

        return Ok(new BootstrapWorkspaceResponse
        {
            BusinessId = biz.Id,
            CreatedBusiness = true,
            Seeded = false,
        });
    }

    [HttpGet("businesses")]
    public async Task<IActionResult> ListBusinesses()
    {
        var user = await GetCurrentUser();

        var rows = await _db.Memberships
            .Where(m => m.UserId == user.Id)
            .Join(_db.Businesses,
                m => m.BusinessId,
                b => b.Id,
                (m, b) => new { Membership = m, Business = b })
            .ToListAsync();

        var result = rows.Select(r => BuildBusinessBrief(r.Business, r.Membership)).ToList();
        return Ok(result);
    }

    [HttpPatch("businesses/{businessId:guid}/branding")]
    public async Task<IActionResult> UpdateBranding(Guid businessId, [FromBody] BusinessBrandingPatchRequest body)
    {
        var user = await GetCurrentUser();
        var membership = await _db.Memberships
            .FirstOrDefaultAsync(m => m.BusinessId == businessId && m.UserId == user.Id);

        if (membership == null || membership.Role != "owner")
            return StatusCode(403, new { detail = "Owner role required" });

        var biz = await _db.Businesses.FirstOrDefaultAsync(b => b.Id == businessId);
        if (biz == null)
            return NotFound(new { detail = "Business not found" });

        if (body.Name != null)
        {
            if (string.IsNullOrWhiteSpace(body.Name))
                return BadRequest(new { detail = "Business name cannot be empty" });
            biz.Name = body.Name.Trim();
        }
        if (body.BrandingTitle != null)
            biz.BrandingTitle = string.IsNullOrWhiteSpace(body.BrandingTitle) ? null : body.BrandingTitle.Trim();
        if (body.BrandingLogoUrl != null)
            biz.BrandingLogoUrl = string.IsNullOrWhiteSpace(body.BrandingLogoUrl) ? null : body.BrandingLogoUrl.Trim();
        if (body.GstNumber != null)
            biz.GstNumber = string.IsNullOrWhiteSpace(body.GstNumber) ? null : body.GstNumber.Trim().ToUpperInvariant();
        if (body.Address != null)
            biz.Address = string.IsNullOrWhiteSpace(body.Address) ? null : body.Address.Trim();
        if (body.Phone != null)
            biz.Phone = string.IsNullOrWhiteSpace(body.Phone) ? null : body.Phone.Trim();
        if (body.ContactEmail != null)
            biz.ContactEmail = string.IsNullOrWhiteSpace(body.ContactEmail) ? null : body.ContactEmail.Trim().ToLowerInvariant();

        await _db.SaveChangesAsync();

        return Ok(BuildBusinessBrief(biz, membership));
    }

    [HttpPost("businesses/{businessId:guid}/branding/logo")]
    public async Task<IActionResult> UploadLogo(Guid businessId, IFormFile file)
    {
        var user = await GetCurrentUser();
        var membership = await _db.Memberships
            .FirstOrDefaultAsync(m => m.BusinessId == businessId && m.UserId == user.Id);

        if (membership == null || membership.Role != "owner")
            return StatusCode(403, new { detail = "Owner role required" });

        if (file == null || file.Length == 0)
            return BadRequest(new { detail = "No file uploaded" });

        var allowedTypes = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["image/jpeg"] = ".jpg",
            ["image/png"] = ".png",
            ["image/webp"] = ".webp",
        };

        var contentType = file.ContentType?.Split(';')[0].Trim().ToLowerInvariant() ?? "";
        if (!allowedTypes.ContainsKey(contentType))
            return BadRequest(new { detail = "Use JPEG, PNG, or WebP" });

        if (file.Length > 2 * 1024 * 1024)
            return BadRequest(new { detail = "Logo must be 2MB or smaller" });

        var biz = await _db.Businesses.FirstOrDefaultAsync(b => b.Id == businessId);
        if (biz == null)
            return NotFound(new { detail = "Business not found" });

        var ext = allowedTypes[contentType];
        var fileName = $"{businessId}{ext}";
        var staticDir = Path.Combine(Directory.GetCurrentDirectory(), "static", "branding");
        Directory.CreateDirectory(staticDir);
        var filePath = Path.Combine(staticDir, fileName);

        await using (var stream = new FileStream(filePath, FileMode.Create))
        {
            await file.CopyToAsync(stream);
        }

        var appUrl = _config.GetValue<string>("AppSettings:AppUrl", "http://localhost:5131").TrimEnd('/');
        biz.BrandingLogoUrl = $"{appUrl}/static/branding/{fileName}";
        await _db.SaveChangesAsync();

        return Ok(BuildBusinessBrief(biz, membership));
    }

    private async Task<User> GetCurrentUser()
    {
        var userIdClaim = User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
        if (userIdClaim == null || !Guid.TryParse(userIdClaim, out var userId))
            throw new UnauthorizedAccessException();

        var user = await _db.Users.FirstOrDefaultAsync(u => u.Id == userId);
        if (user == null || user.DeletedAt != null || user.IsBlocked || !user.IsActive)
            throw new UnauthorizedAccessException();

        var tvClaim = User.FindFirst("tv")?.Value;
        var expectedTv = int.TryParse(tvClaim, out var tv) ? tv : 0;
        if (user.TokenVersion != expectedTv)
            throw new UnauthorizedAccessException();

        return user;
    }

    private BusinessBriefResponse BuildBusinessBrief(Business biz, Membership membership)
    {
        var perms = ComputeEffectivePermissions(membership.Role, membership.PermissionsJson);
        return new BusinessBriefResponse
        {
            Id = biz.Id,
            Name = biz.Name,
            Role = membership.Role,
            Permissions = perms,
            BrandingTitle = biz.BrandingTitle,
            BrandingLogoUrl = biz.BrandingLogoUrl,
            GstNumber = biz.GstNumber,
            Address = biz.Address,
            Phone = biz.Phone,
            ContactEmail = biz.ContactEmail,
        };
    }

    private static Dictionary<string, bool> ComputeEffectivePermissions(string role, string? permissionsJson)
    {
        var _permissionKeys = new[] { "stock_edit", "purchase_create", "purchase_edit", "barcode_print", "reports_access", "export_access", "user_manage", "delete_access", "analytics_access" };

        var roleDefaults = new Dictionary<string, Dictionary<string, bool>>
        {
            ["owner"] = _permissionKeys.ToDictionary(k => k, _ => true),
            ["admin"] = _permissionKeys.ToDictionary(k => k, _ => true),
            ["manager"] = new Dictionary<string, bool>
            {
                ["stock_edit"] = true, ["purchase_create"] = true, ["purchase_edit"] = true,
                ["reports_access"] = true, ["barcode_print"] = true, ["export_access"] = true,
                ["user_manage"] = false, ["delete_access"] = false, ["analytics_access"] = true,
            },
            ["staff"] = new Dictionary<string, bool>
            {
                ["stock_edit"] = true, ["purchase_create"] = true, ["purchase_edit"] = false,
                ["reports_access"] = false, ["barcode_print"] = true, ["export_access"] = false,
                ["user_manage"] = false, ["delete_access"] = false, ["analytics_access"] = false,
            },
        };

        var basePerms = roleDefaults.GetValueOrDefault(role, roleDefaults["staff"]);
        var result = new Dictionary<string, bool>(basePerms);

        if (!string.IsNullOrEmpty(permissionsJson))
        {
            var overrides = System.Text.Json.JsonSerializer.Deserialize<Dictionary<string, bool>>(permissionsJson);
            if (overrides != null)
            {
                foreach (var key in _permissionKeys)
                {
                    if (overrides.TryGetValue(key, out var val))
                        result[key] = val;
                }
            }
        }

        return result;
    }
}
