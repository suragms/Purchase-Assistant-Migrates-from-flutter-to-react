using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using PurchaseAssistant.Application.Common.Interfaces;
using PurchaseAssistant.Application.Features.Users.Dtos;
using PurchaseAssistant.Domain.Entities.Activity;
using PurchaseAssistant.Domain.Entities.Catalog;
using PurchaseAssistant.Domain.Entities.Contacts;
using PurchaseAssistant.Domain.Entities.Core;
using PurchaseAssistant.Domain.Entities.Stock;
using PurchaseAssistant.Domain.Entities.Trade;
using PurchaseAssistant.Infrastructure.Data;

namespace PurchaseAssistant.Api.Controllers;

[ApiController]
[Route("v1/businesses/{businessId:guid}/users")]
public class UsersController : ControllerBase
{
    private readonly PurchaseAssistantDbContext _db;
    private readonly IPasswordService _password;
    private readonly IUsernameService _usernameService;

    public UsersController(
        PurchaseAssistantDbContext db,
        IPasswordService password,
        IUsernameService usernameService)
    {
        _db = db;
        _password = password;
        _usernameService = usernameService;
    }

    [HttpPost]
    [Authorize]
    public async Task<IActionResult> CreateUser(Guid businessId, [FromBody] UserCreateRequest body)
    {
        var (currentUser, membership) = await GetCurrentUserWithMembership(businessId);
        if (!currentUser.IsSuperAdmin && membership.Role != "owner" && membership.Role != "admin")
            return Forbid();

        if (membership.Role == "admin" && body.Role == "owner")
            return StatusCode(403, new { detail = "Cannot create owner accounts" });

        var digits = System.Text.RegularExpressions.Regex.Replace(body.Phone ?? "", @"\D", "");
        if (digits.Length < 6)
            return BadRequest(new { detail = "Invalid phone" });

        var email = body.Email;
        if (string.IsNullOrWhiteSpace(email))
        {
            digits = System.Text.RegularExpressions.Regex.Replace(body.Phone ?? "", @"\D", "");
            if (digits.Length < 6)
                return BadRequest(new { detail = "Invalid phone" });
            email = $"{digits}@staff.harisree.local";
        }
        else
        {
            email = email.Trim().ToLowerInvariant();
        }

        string username;
        try
        {
            username = await _usernameService.AllocateUsername(null, digits, body.FullName);
        }
        catch (ArgumentException)
        {
            return Conflict(new { detail = "Username already taken" });
        }

        var emailExists = await _db.Users.AnyAsync(u => u.Email == email && u.DeletedAt == null);
        if (emailExists)
            return Conflict(new { detail = "Email already registered" });

        var plain = !string.IsNullOrWhiteSpace(body.Password)
            ? body.Password.Trim()
            : _password.GenerateReadablePassword(body.FullName);

        var user = new User
        {
            Email = email,
            Username = username,
            PasswordHash = _password.Hash(plain),
            Phone = body.Phone.Trim(),
            Name = body.FullName.Trim(),
            IsActive = body.IsActive,
            IsBlocked = false,
            Notes = body.Notes?.Trim(),
            CreatedBy = currentUser.Id,
        };
        _db.Users.Add(user);
        await _db.SaveChangesAsync();

        var mem = new Membership
        {
            UserId = user.Id,
            BusinessId = businessId,
            Role = body.Role,
        };
        _db.Memberships.Add(mem);
        await _db.SaveChangesAsync();

        _db.StaffActivityLogs.Add(new StaffActivityLog
        {
            BusinessId = businessId,
            UserId = currentUser.Id,
            UserName = currentUser.Name ?? currentUser.Username,
            ActionType = "USER_CREATE",
            ItemName = user.Name,
            CreatedAt = DateTime.UtcNow,
        });
        await _db.SaveChangesAsync();

        var row = await BuildUserRow(businessId, user, mem);
        return StatusCode(201, new UserCreateResponseDto
        {
            User = row,
            GeneratedPassword = string.IsNullOrWhiteSpace(body.Password) ? plain : null,
            LoginEmail = email,
        });
    }

    [HttpGet]
    [Authorize]
    public async Task<IActionResult> ListUsers(
        Guid businessId,
        [FromQuery] bool includeInactive = false)
    {
        var (_, membership) = await GetCurrentUserWithMembership(businessId);
        if (!new[] { "owner", "admin", "manager" }.Contains(membership.Role))
            return Forbid();

        var query = _db.Users
            .Join(_db.Memberships.Where(m => m.BusinessId == businessId),
                u => u.Id,
                m => m.UserId,
                (u, m) => new { u, m })
            .Where(x => x.u.DeletedAt == null);

        if (!includeInactive)
            query = query.Where(x => x.u.IsActive);

        var rows = await query.OrderBy(x => x.u.Name).ToListAsync();

        var result = new List<UserListDto>();
        foreach (var row in rows)
            result.Add(await BuildUserRow(businessId, row.u, row.m));
        return Ok(result);
    }

    [HttpGet("active-sessions")]
    [Authorize]
    public async Task<IActionResult> GetActiveSessions(Guid businessId)
    {
        var (currentUser, membership) = await GetCurrentUserWithMembership(businessId);
        if (!currentUser.IsSuperAdmin && membership.Role != "owner" && membership.Role != "manager")
            return Forbid();

        var cutoff = DateTime.UtcNow.AddMinutes(-5);
        var rows = await _db.Users
            .Join(_db.Memberships.Where(m => m.BusinessId == businessId),
                u => u.Id,
                m => m.UserId,
                (u, m) => new { u, m })
            .Where(x => x.u.LastActiveAt != null && x.u.LastActiveAt >= cutoff && x.u.IsActive && x.u.DeletedAt == null)
            .OrderBy(x => x.u.Name)
            .ToListAsync();

        var result = new List<UserListDto>();
        foreach (var row in rows)
            result.Add(await BuildUserRow(businessId, row.u, row.m));
        return Ok(result);
    }

    [HttpPost("bulk")]
    [Authorize]
    public async Task<IActionResult> BulkAction(Guid businessId, [FromBody] UserBulkRequest body)
    {
        var (currentUser, membership) = await GetCurrentUserWithMembership(businessId);
        if (!currentUser.IsSuperAdmin && membership.Role != "owner" && membership.Role != "admin")
            return Forbid();

        var updated = 0;
        var failed = new List<string>();

        foreach (var uid in body.UserIds)
        {
            var row = await _db.Users
                .Join(_db.Memberships.Where(m => m.BusinessId == businessId),
                    u => u.Id,
                    m => m.UserId,
                    (u, m) => new { u, m })
                .FirstOrDefaultAsync(x => x.u.Id == uid && x.u.DeletedAt == null);

            if (row == null)
            {
                failed.Add(uid.ToString());
                continue;
            }

            if (!currentUser.IsSuperAdmin && !CanManageTarget(membership.Role, row.m.Role))
            {
                failed.Add(uid.ToString());
                continue;
            }

            if (row.u.Id == currentUser.Id && body.Action is "deactivate" or "delete" or "block")
            {
                failed.Add(uid.ToString());
                continue;
            }

            switch (body.Action)
            {
                case "activate":
                    row.u.IsActive = true;
                    row.u.DeletedAt = null;
                    row.u.IsBlocked = false;
                    break;
                case "deactivate":
                    row.u.IsActive = false;
                    break;
                case "block":
                    row.u.IsBlocked = true;
                    row.u.TokenVersion++;
                    _db.StaffActivityLogs.Add(new StaffActivityLog
                    {
                        BusinessId = businessId,
                        UserId = currentUser.Id,
                        UserName = currentUser.Name ?? currentUser.Username,
                        ActionType = "USER_BLOCK",
                        ItemName = row.u.Name,
                        CreatedAt = DateTime.UtcNow,
                    });
                    break;
                case "unblock":
                    row.u.IsBlocked = false;
                    break;
                case "delete":
                    row.u.IsActive = false;
                    row.u.DeletedAt = DateTime.UtcNow;
                    row.u.TokenVersion++;
                    _db.StaffActivityLogs.Add(new StaffActivityLog
                    {
                        BusinessId = businessId,
                        UserId = currentUser.Id,
                        UserName = currentUser.Name ?? currentUser.Username,
                        ActionType = "USER_DELETE",
                        ItemName = row.u.Name,
                        CreatedAt = DateTime.UtcNow,
                    });
                    break;
                case "set_role":
                    if (string.IsNullOrEmpty(body.Role))
                    { failed.Add(uid.ToString()); continue; }
                    if (membership.Role == "admin" && body.Role == "owner")
                    { failed.Add(uid.ToString()); continue; }
                    row.m.Role = body.Role;
                    break;
            }
            updated++;
        }

        await _db.SaveChangesAsync();
        return Ok(new UserBulkResponseDto { Updated = updated, Failed = failed });
    }

    [HttpGet("{userId:guid}")]
    [Authorize]
    public async Task<IActionResult> GetUser(Guid businessId, Guid userId)
    {
        var (_, membership) = await GetCurrentUserWithMembership(businessId);
        if (!new[] { "owner", "admin", "manager" }.Contains(membership.Role))
            return Forbid();

        var row = await LoadUserMembership(businessId, userId);
        if (row == null)
            return NotFound(new { detail = "User not found" });

        return Ok(await BuildUserRow(businessId, row.Value.User, row.Value.Membership, profile: true));
    }

    [HttpPatch("{userId:guid}")]
    [Authorize]
    public async Task<IActionResult> UpdateUser(Guid businessId, Guid userId, [FromBody] UserPatchRequest body)
    {
        var (currentUser, membership) = await GetCurrentUserWithMembership(businessId);
        if (!currentUser.IsSuperAdmin && membership.Role != "owner" && membership.Role != "admin")
            return Forbid();

        var row = await LoadUserMembership(businessId, userId);
        if (row == null)
            return NotFound(new { detail = "User not found" });

        var (user, mem) = row.Value;

        if (!currentUser.IsSuperAdmin && !CanManageTarget(membership.Role, mem.Role))
            return StatusCode(403, new { detail = "You cannot modify this user" });
        if (!currentUser.IsSuperAdmin && mem.Role == "owner" && membership.Role != "owner")
            return StatusCode(403, new { detail = "Owner account is protected" });

        if (body.FullName != null)
            user.Name = body.FullName.Trim();
        if (body.Email != null)
        {
            var emailExists = await _db.Users.AnyAsync(u => u.Email == body.Email && u.Id != userId && u.DeletedAt == null);
            if (emailExists)
                return Conflict(new { detail = "Email already registered" });
            user.Email = body.Email;
        }
        if (body.Phone != null)
            user.Phone = body.Phone.Trim();
        if (body.Role != null)
        {
            if (membership.Role == "admin" && body.Role == "owner")
                return StatusCode(403, new { detail = "Cannot assign owner role" });
            mem.Role = body.Role;
        }
        if (body.IsActive.HasValue)
        {
            user.IsActive = body.IsActive.Value;
            if (body.IsActive.Value)
            {
                user.DeletedAt = null;
                user.IsBlocked = false;
            }
        }
        if (body.IsBlocked.HasValue)
        {
            user.IsBlocked = body.IsBlocked.Value;
            if (body.IsBlocked.Value)
            {
                user.TokenVersion++;
                _db.StaffActivityLogs.Add(new StaffActivityLog
                {
                    BusinessId = businessId,
                    UserId = currentUser.Id,
                    UserName = currentUser.Name ?? currentUser.Username,
                    ActionType = "USER_BLOCK",
                    ItemName = user.Name,
                    CreatedAt = DateTime.UtcNow,
                });
            }
        }
        if (body.Notes != null)
            user.Notes = body.Notes.Trim() ?? null;

        await _db.SaveChangesAsync();
        return Ok(await BuildUserRow(businessId, user, mem));
    }

    [HttpDelete("{userId:guid}")]
    [Authorize]
    public async Task<IActionResult> DeleteUser(Guid businessId, Guid userId)
    {
        var (currentUser, membership) = await GetCurrentUserWithMembership(businessId);
        if (!currentUser.IsSuperAdmin && membership.Role != "owner" && membership.Role != "admin")
            return Forbid();

        var row = await LoadUserMembership(businessId, userId);
        if (row == null)
            return NotFound(new { detail = "User not found" });

        var (user, mem) = row.Value;

        if (!currentUser.IsSuperAdmin && !CanManageTarget(membership.Role, mem.Role))
            return StatusCode(403, new { detail = "You cannot modify this user" });
        if (!currentUser.IsSuperAdmin && mem.Role == "owner" && membership.Role != "owner")
            return StatusCode(403, new { detail = "Owner account is protected" });
        if (user.Id == currentUser.Id)
            return BadRequest(new { detail = "Cannot delete your own account" });

        user.IsActive = false;
        user.DeletedAt = DateTime.UtcNow;
        user.TokenVersion++;

        _db.StaffActivityLogs.Add(new StaffActivityLog
        {
            BusinessId = businessId,
            UserId = currentUser.Id,
            UserName = currentUser.Name ?? currentUser.Username,
            ActionType = "USER_DELETE",
            ItemName = user.Name,
            CreatedAt = DateTime.UtcNow,
        });
        await _db.SaveChangesAsync();

        return NoContent();
    }

    [HttpPost("{userId:guid}/reset-password")]
    [Authorize]
    public async Task<IActionResult> ResetPassword(Guid businessId, Guid userId)
    {
        var (currentUser, membership) = await GetCurrentUserWithMembership(businessId);
        if (!currentUser.IsSuperAdmin && membership.Role != "owner" && membership.Role != "admin")
            return Forbid();

        var row = await LoadUserMembership(businessId, userId);
        if (row == null)
            return NotFound(new { detail = "User not found" });

        var (user, mem) = row.Value;

        if (!currentUser.IsSuperAdmin && !CanManageTarget(membership.Role, mem.Role))
            return StatusCode(403, new { detail = "You cannot modify this user" });

        var plain = _password.GenerateReadablePassword(user.Name);
        user.PasswordHash = _password.Hash(plain);

        _db.StaffActivityLogs.Add(new StaffActivityLog
        {
            BusinessId = businessId,
            UserId = currentUser.Id,
            UserName = currentUser.Name ?? currentUser.Username,
            ActionType = "PASSWORD_RESET",
            ItemName = user.Name,
            CreatedAt = DateTime.UtcNow,
        });
        await _db.SaveChangesAsync();

        return Ok(new ResetPasswordResponseDto
        {
            NewPassword = plain,
            LoginEmail = user.Email,
        });
    }

    [HttpGet("{userId:guid}/credentials")]
    [Authorize]
    public async Task<IActionResult> GetCredentials(Guid businessId, Guid userId)
    {
        var (_, membership) = await GetCurrentUserWithMembership(businessId);
        if (!new[] { "owner", "admin" }.Contains(membership.Role))
            return Forbid();

        var row = await LoadUserMembership(businessId, userId);
        if (row == null)
            return NotFound(new { detail = "User not found" });

        return Ok(new CredentialsResponseDto
        {
            Username = row.Value.User.Username,
            LoginEmail = row.Value.User.Email,
            Phone = row.Value.User.Phone,
        });
    }

    [HttpGet("{userId:guid}/created-items")]
    [Authorize]
    public async Task<IActionResult> GetCreatedItems(
        Guid businessId, Guid userId,
        [FromQuery] int limit = 50)
    {
        var (_, membership) = await GetCurrentUserWithMembership(businessId);
        if (!new[] { "owner", "admin", "manager" }.Contains(membership.Role))
            return Forbid();

        var items = await _db.CatalogItems
            .Where(i => i.BusinessId == businessId && i.CreatedByUserId == userId && i.DeletedAt == null)
            .OrderByDescending(i => i.CreatedAt)
            .Take(limit)
            .Select(i => new CreatedItemDto
            {
                Id = i.Id,
                Name = i.Name,
                Barcode = i.ItemCode,
                ReorderLevel = i.ReorderLevel,
                UpdatedAt = i.LastStockUpdatedAt ?? i.CreatedAt,
            })
            .ToListAsync();

        return Ok(items);
    }

    [HttpGet("{userId:guid}/stock-adjustments")]
    [Authorize]
    public async Task<IActionResult> GetStockAdjustments(
        Guid businessId, Guid userId,
        [FromQuery] int limit = 50)
    {
        var (_, membership) = await GetCurrentUserWithMembership(businessId);
        if (!new[] { "owner", "manager" }.Contains(membership.Role))
            return Forbid();

        var adjustments = await _db.StockAdjustmentLogs
            .Where(s => s.BusinessId == businessId && s.UpdatedBy == userId)
            .OrderByDescending(s => s.UpdatedAt)
            .Take(limit)
            .Join(_db.CatalogItems,
                s => s.ItemId,
                i => i.Id,
                (s, i) => new StockAdjustmentDto
                {
                    Id = s.Id,
                    ItemId = s.ItemId,
                    ItemName = i.Name,
                    OldQty = s.OldQty.GetValueOrDefault(),
                    NewQty = s.NewQty.GetValueOrDefault(),
                    AdjustmentType = s.AdjustmentType ?? "",
                    Reason = s.Reason,
                    UpdatedAt = s.UpdatedAt.GetValueOrDefault(),
                })
            .ToListAsync();

        return Ok(adjustments);
    }

    [HttpGet("{userId:guid}/purchases")]
    [Authorize]
    public async Task<IActionResult> GetPurchases(
        Guid businessId, Guid userId,
        [FromQuery] int limit = 50)
    {
        var (_, membership) = await GetCurrentUserWithMembership(businessId);
        if (!new[] { "owner", "admin", "manager" }.Contains(membership.Role))
            return Forbid();

        var purchases = await _db.TradePurchases
            .Where(p => p.BusinessId == businessId && p.UserId == userId)
            .OrderByDescending(p => p.CreatedAt)
            .Take(limit)
            .Join(_db.Suppliers,
                p => p.SupplierId,
                s => s.Id,
                (p, s) => new { p, SupplierName = s.Name })
            .Select(x => new UserPurchaseBriefDto
            {
                Id = x.p.Id,
                HumanId = x.p.HumanId,
                PurchaseDate = x.p.PurchaseDate.ToDateTime(TimeOnly.MinValue, DateTimeKind.Utc),
                Status = x.p.Status,
                TotalAmount = x.p.TotalAmount,
                SupplierName = x.SupplierName,
                ItemCount = _db.TradePurchaseLines.Count(l => l.TradePurchaseId == x.p.Id),
            })
            .ToListAsync();

        return Ok(purchases);
    }

    [HttpGet("{userId:guid}/ledger")]
    [Authorize]
    public async Task<IActionResult> GetLedger(
        Guid businessId, Guid userId,
        [FromQuery] int limit = 80,
        [FromQuery] bool grouped = false)
    {
        var (_, membership) = await GetCurrentUserWithMembership(businessId);
        if (!new[] { "owner", "admin", "manager" }.Contains(membership.Role))
            return Forbid();

        var entries = new List<LedgerEntryDto>();

        var activities = await _db.StaffActivityLogs
            .Where(a => a.BusinessId == businessId && a.UserId == userId)
            .OrderByDescending(a => a.CreatedAt)
            .Take(limit)
            .ToListAsync();

        foreach (var a in activities)
        {
            entries.Add(new LedgerEntryDto
            {
                Kind = "activity",
                At = a.CreatedAt,
                Title = a.ActionType,
                Subtitle = a.ItemName,
            });
        }

        var stockLogs = await _db.StockAdjustmentLogs
            .Where(s => s.BusinessId == businessId && s.UpdatedBy == userId)
            .OrderByDescending(s => s.UpdatedAt)
            .Take(limit)
            .Join(_db.CatalogItems,
                s => s.ItemId,
                i => i.Id,
                (s, i) => new { s, ItemName = i.Name })
            .ToListAsync();

        foreach (var log in stockLogs)
        {
            entries.Add(new LedgerEntryDto
            {
                Kind = "stock",
                At = log.s.UpdatedAt.GetValueOrDefault(),
                Title = "STOCK_UPDATE",
                Subtitle = log.ItemName,
                Details = new Dictionary<string, object>
                {
                    ["old_qty"] = (double)log.s.OldQty,
                    ["new_qty"] = (double)log.s.NewQty,
                },
            });
        }

        entries = entries.OrderByDescending(e => e.At).Take(limit).ToList();

        if (!grouped)
            return Ok(entries);

        var now = DateTime.UtcNow;
        var todayStart = now.Date;
        var yesterdayStart = todayStart.AddDays(-1);
        var weekStart = todayStart.AddDays(-7);

        var groupedResult = new LedgerGroupedDto();
        foreach (var e in entries)
        {
            if (e.At >= todayStart)
                groupedResult.Today.Add(e);
            else if (e.At >= yesterdayStart)
                groupedResult.Yesterday.Add(e);
            else if (e.At >= weekStart)
                groupedResult.ThisWeek.Add(e);
        }
        return Ok(groupedResult);
    }

    [HttpGet("{userId:guid}/permissions")]
    [Authorize]
    public async Task<IActionResult> GetPermissions(Guid businessId, Guid userId)
    {
        var (_, membership) = await GetCurrentUserWithMembership(businessId);
        if (!new[] { "owner", "admin" }.Contains(membership.Role))
            return Forbid();

        var row = await LoadUserMembership(businessId, userId);
        if (row == null)
            return NotFound(new { detail = "User not found" });

        var perms = ComputeEffectivePermissions(row.Value.Membership.Role, row.Value.Membership.PermissionsJson);
        return Ok(new PermissionsDto
        {
            Role = row.Value.Membership.Role,
            Permissions = perms,
        });
    }

    [HttpPatch("{userId:guid}/permissions")]
    [Authorize]
    public async Task<IActionResult> UpdatePermissions(Guid businessId, Guid userId, [FromBody] PermissionsPatchRequest body)
    {
        var (_, membership) = await GetCurrentUserWithMembership(businessId);
        if (!new[] { "owner", "admin" }.Contains(membership.Role))
            return Forbid();

        var row = await LoadUserMembership(businessId, userId);
        if (row == null)
            return NotFound(new { detail = "User not found" });

        var currentPerms = string.IsNullOrEmpty(row.Value.Membership.PermissionsJson)
            ? new Dictionary<string, bool>()
            : System.Text.Json.JsonSerializer.Deserialize<Dictionary<string, bool>>(row.Value.Membership.PermissionsJson) ?? new();

        var merged = new Dictionary<string, bool>(currentPerms);
        var permissionKeys = new[] { "stock_edit", "purchase_create", "purchase_edit", "barcode_print", "reports_access", "export_access", "user_manage", "delete_access", "analytics_access" };
        foreach (var kv in body.Permissions)
        {
            if (permissionKeys.Contains(kv.Key))
                merged[kv.Key] = kv.Value;
        }

        row.Value.Membership.PermissionsJson = System.Text.Json.JsonSerializer.Serialize(merged);
        await _db.SaveChangesAsync();

        var perms = ComputeEffectivePermissions(row.Value.Membership.Role, System.Text.Json.JsonSerializer.Serialize(merged));
        return Ok(new PermissionsDto
        {
            Role = row.Value.Membership.Role,
            Permissions = perms,
        });
    }

    private async Task<(User User, Membership Membership)> GetCurrentUserWithMembership(Guid businessId)
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

        var membership = await _db.Memberships.FirstOrDefaultAsync(m => m.BusinessId == businessId && m.UserId == userId);
        if (membership == null)
            throw new UnauthorizedAccessException();

        return (user, membership);
    }

    private async Task<UserListDto> BuildUserRow(Guid businessId, User user, Membership membership, bool profile = false)
    {
        var todayStart = DateTime.UtcNow.Date;

        var scans = await _db.StaffActivityLogs.CountAsync(a =>
            a.BusinessId == businessId && a.UserId == user.Id && a.ActionType == "SCAN" && a.CreatedAt >= todayStart);
        var stockUpdates = await _db.StaffActivityLogs.CountAsync(a =>
            a.BusinessId == businessId && a.UserId == user.Id && a.ActionType == "STOCK_UPDATE" && a.CreatedAt >= todayStart);
        var itemsCreated = await _db.StaffActivityLogs.CountAsync(a =>
            a.BusinessId == businessId && a.UserId == user.Id && a.ActionType == "ITEM_CREATE" && a.CreatedAt >= todayStart);

        var activity7d = await _db.StaffActivityLogs.CountAsync(a =>
            a.BusinessId == businessId && a.UserId == user.Id && a.CreatedAt >= DateTime.UtcNow.AddDays(-7));

        var warehouseName = await _db.Businesses.Where(b => b.Id == businessId).Select(b => b.Name).FirstOrDefaultAsync();

        var result = new UserListDto
        {
            Id = user.Id,
            Name = user.Name,
            Phone = user.Phone,
            Email = user.Email,
            Username = user.Username,
            Role = membership.Role,
            IsActive = user.IsActive,
            IsBlocked = user.IsBlocked,
            LastLoginAt = user.LastLoginAt,
            LastActiveAt = user.LastActiveAt,
            TodayStats = new TodayStatsDto
            {
                Scans = scans,
                StockUpdates = stockUpdates,
                ItemsCreated = itemsCreated,
            },
            WarehouseName = warehouseName,
            ActivityCount7D = activity7d,
            Notes = user.Notes,
            CreatedAt = user.CreatedAt,
        };

        if (!profile)
            return result;

        var purchases7d = await _db.TradePurchases.CountAsync(p =>
            p.BusinessId == businessId && p.UserId == user.Id && p.CreatedAt >= DateTime.UtcNow.AddDays(-7));
        var stockEdits7d = await _db.StockAdjustmentLogs.CountAsync(s =>
            s.BusinessId == businessId && s.UpdatedBy == user.Id && s.UpdatedAt >= DateTime.UtcNow.AddDays(-7));

        var stockEditsTotal = await _db.StockAdjustmentLogs.CountAsync(s =>
            s.BusinessId == businessId && s.UpdatedBy == user.Id);
        var purchasesTotal = await _db.TradePurchases.CountAsync(p =>
            p.BusinessId == businessId && p.UserId == user.Id);
        var scansTotal = await _db.StaffActivityLogs.CountAsync(a =>
            a.BusinessId == businessId && a.UserId == user.Id && a.ActionType == "SCAN");
        var itemsCreatedTotal = await _db.CatalogItems.CountAsync(i =>
            i.BusinessId == businessId && i.CreatedByUserId == user.Id && i.DeletedAt == null);

        return new UserProfileDto
        {
            Id = result.Id,
            Name = result.Name,
            Phone = result.Phone,
            Email = result.Email,
            Username = result.Username,
            Role = result.Role,
            IsActive = result.IsActive,
            IsBlocked = result.IsBlocked,
            LastLoginAt = result.LastLoginAt,
            LastActiveAt = result.LastActiveAt,
            TodayStats = result.TodayStats,
            WarehouseName = result.WarehouseName,
            ActivityCount7D = result.ActivityCount7D,
            Notes = result.Notes,
            CreatedAt = result.CreatedAt,
            LoginEmail = user.Email,
            Purchases7D = purchases7d,
            StockUpdates7D = stockEdits7d,
            Stats = new ProfileStatsDto
            {
                StockEditsTotal = stockEditsTotal,
                PurchasesTotal = purchasesTotal,
                ScansTotal = scansTotal,
                ItemsCreatedTotal = itemsCreatedTotal,
            },
        };
    }

    private async Task<(User User, Membership Membership)?> LoadUserMembership(Guid businessId, Guid userId)
    {
        var user = await _db.Users.FirstOrDefaultAsync(u => u.Id == userId && u.DeletedAt == null);
        if (user == null) return null;
        var mem = await _db.Memberships.FirstOrDefaultAsync(m => m.BusinessId == businessId && m.UserId == userId);
        if (mem == null) return null;
        return (user, mem);
    }

    private static bool CanManageTarget(string actorRole, string targetRole)
    {
        if (targetRole == "owner" && actorRole == "admin")
            return false;
        return true;
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

[ApiController]
[Route("v1/businesses/{businessId:guid}/activity-log")]
public class ActivityLogController : ControllerBase
{
    private readonly PurchaseAssistantDbContext _db;

    public ActivityLogController(PurchaseAssistantDbContext db)
    {
        _db = db;
    }

    [HttpPost]
    [Authorize]
    public async Task<IActionResult> PostActivity(
        Guid businessId,
        [FromBody] ActivityLogRequest body)
    {
        var (currentUser, _) = await GetCurrentUser(businessId);

        var row = new StaffActivityLog
        {
            BusinessId = businessId,
            UserId = currentUser.Id,
            UserName = currentUser.Name ?? currentUser.Username,
            ActionType = body.ActionType,
            ItemId = body.ItemId,
            ItemName = body.ItemName,
            Details = body.Details != null ? System.Text.Json.JsonSerializer.Serialize(body.Details) : null,
        };
        _db.StaffActivityLogs.Add(row);
        currentUser.LastActiveAt = DateTime.UtcNow;
        await _db.SaveChangesAsync();

        return StatusCode(201, new ActivityLogDto
        {
            Id = row.Id,
            UserName = row.UserName,
            ActionType = row.ActionType,
            ItemId = row.ItemId,
            ItemName = row.ItemName,
            Details = row.Details != null ? System.Text.Json.JsonSerializer.Deserialize<Dictionary<string, object>>(row.Details) : null,
            CreatedAt = row.CreatedAt,
        });
    }

    [HttpGet]
    [Authorize]
    public async Task<IActionResult> ListActivity(
        Guid businessId,
        [FromQuery] Guid? userId = null,
        [FromQuery] string period = "today",
        [FromQuery] int? days = null,
        [FromQuery] int page = 1,
        [FromQuery] int perPage = 50)
    {
        var (currentUser, _) = await GetCurrentUser(businessId);
        var uid = userId ?? currentUser.Id;

        DateTime start;
        var now = DateTime.UtcNow;
        if (days.HasValue)
            start = now.AddDays(-days.Value);
        else
            start = period switch
            {
                "week" => now.AddDays(-7),
                "month" => now.AddDays(-30),
                _ => now.Date,
            };

        var activities = await _db.StaffActivityLogs
            .Where(a => a.BusinessId == businessId && a.UserId == uid && a.CreatedAt >= start)
            .OrderByDescending(a => a.CreatedAt)
            .Skip((page - 1) * perPage)
            .Take(perPage)
            .ToListAsync();

        return Ok(activities.Select(a => new ActivityLogDto
        {
            Id = a.Id,
            UserName = a.UserName,
            ActionType = a.ActionType,
            ItemId = a.ItemId,
            ItemName = a.ItemName,
            Details = a.Details != null ? System.Text.Json.JsonSerializer.Deserialize<Dictionary<string, object>>(a.Details) : null,
            CreatedAt = a.CreatedAt,
        }));
    }

    private async Task<(Domain.Entities.Core.User User, Membership? Membership)> GetCurrentUser(Guid businessId)
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

        var membership = await _db.Memberships.FirstOrDefaultAsync(m => m.BusinessId == businessId && m.UserId == userId);
        return (user, membership);
    }
}
