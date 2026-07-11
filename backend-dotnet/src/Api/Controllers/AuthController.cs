using System.Security.Claims;
using System.Security.Cryptography;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using PurchaseAssistant.Application.Common.Interfaces;
using PurchaseAssistant.Application.Features.Auth.Dtos;
using PurchaseAssistant.Domain.Entities.Activity;
using PurchaseAssistant.Domain.Entities.Core;
using PurchaseAssistant.Infrastructure.Data;

namespace PurchaseAssistant.Api.Controllers;

[ApiController]
[Route("v1/auth")]
public class AuthController : ControllerBase
{
    private readonly PurchaseAssistantDbContext _db;
    private readonly IJwtService _jwt;
    private readonly IPasswordService _password;
    private readonly IGoogleOAuthService _googleOAuth;
    private readonly IPermissionService _permissions;
    private readonly IConfiguration _config;
    private readonly ILogger<AuthController> _logger;

    public AuthController(
        PurchaseAssistantDbContext db,
        IJwtService jwt,
        IPasswordService password,
        IGoogleOAuthService googleOAuth,
        IPermissionService permissions,
        IConfiguration config,
        ILogger<AuthController> logger)
    {
        _db = db;
        _jwt = jwt;
        _password = password;
        _googleOAuth = googleOAuth;
        _permissions = permissions;
        _config = config;
        _logger = logger;
    }

    [HttpPost("register")]
    public async Task<IActionResult> Register([FromBody] RegisterRequest body)
    {
        var allowPublic = _config.GetValue<bool>("AppSettings:AllowPublicRegistration");
        if (!allowPublic)
            return StatusCode(403, new
            {
                detail = "Self-registration is disabled. Ask your workspace owner to create your account from Settings → Users."
            });

        var email = body.Email.Trim().ToLowerInvariant();
        var username = body.Username.Trim().ToLowerInvariant();

        var exists = await _db.Users.AnyAsync(u => u.Email == email || u.Username == username);
        if (exists)
            return Conflict(new { detail = "An account with this email or username already exists" });

        string pwdHash;
        try
        {
            pwdHash = _password.Hash(body.Password);
        }
        catch (ArgumentException ex)
        {
            return UnprocessableEntity(new { detail = ex.Message });
        }

        var user = new User
        {
            Email = email,
            Username = username,
            PasswordHash = pwdHash,
            Phone = null,
            Name = body.Name?.Trim(),
        };

        var superadminEmail = _config.GetValue<string>("AppSettings:SuperadminBootstrapEmail");
        if (!string.IsNullOrEmpty(superadminEmail) && email == superadminEmail.Trim().ToLowerInvariant())
            user.IsSuperAdmin = true;

        _db.Users.Add(user);
        await _db.SaveChangesAsync();

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

        var access = _jwt.CreateAccessToken(user.Id, user.TokenVersion);
        var refresh = _jwt.CreateRefreshToken(user.Id);
        var ttl = _config.GetValue<int>("Jwt:AccessTtlMinutes", 15);

        return Ok(new TokenPairResponse
        {
            AccessToken = access,
            RefreshToken = refresh,
            ExpiresIn = ttl * 60,
        });
    }

    [HttpPost("login")]
    public async Task<IActionResult> Login([FromBody] LoginRequest body)
    {
        var raw = (body.Email ?? body.Identifier ?? "").Trim().ToLowerInvariant();
        if (string.IsNullOrEmpty(raw) || !raw.Contains('@'))
            return Unauthorized(new { detail = "Invalid email or password" });

        var user = await _db.Users.FirstOrDefaultAsync(u => u.Email == raw);
        if (user == null || user.PasswordHash == null || !_password.Verify(body.Password, user.PasswordHash))
            return Unauthorized(new { detail = "Invalid email or password" });
        if (user.DeletedAt != null)
            return StatusCode(403, new { detail = "Account is inactive" });
        if (user.IsBlocked)
            return StatusCode(403, new { detail = "Account is blocked" });
        if (!user.IsActive)
            return StatusCode(403, new { detail = "Account is inactive" });

        var now = DateTime.UtcNow;
        user.LastLoginAt = now;
        user.LastActiveAt = now;

        if (!string.IsNullOrWhiteSpace(body.DeviceToken))
        {
            var info = string.IsNullOrEmpty(user.DeviceInfo) ? new Dictionary<string, object>() : System.Text.Json.JsonSerializer.Deserialize<Dictionary<string, object>>(user.DeviceInfo) ?? new();
            info["push_token"] = body.DeviceToken.Trim()[..Math.Min(512, body.DeviceToken.Length)];
            info["push_token_updated_at"] = now.ToString("O");
            user.DeviceInfo = System.Text.Json.JsonSerializer.Serialize(info);
        }

        var membership = await _db.Memberships.FirstOrDefaultAsync(m => m.UserId == user.Id);

        _db.UserSessions.Add(new UserSession
        {
            UserId = user.Id,
            BusinessId = membership?.BusinessId,
            LoginAt = now,
            IsActive = true,
        });

        if (membership != null)
        {
            _db.StaffActivityLogs.Add(new StaffActivityLog
            {
                BusinessId = membership.BusinessId,
                UserId = user.Id,
                UserName = user.Name ?? user.Username,
                ActionType = "LOGIN",
                CreatedAt = now,
            });
        }

        await _db.SaveChangesAsync();

        var access = _jwt.CreateAccessToken(user.Id, user.TokenVersion);
        var refresh = _jwt.CreateRefreshToken(user.Id);
        var ttl = _config.GetValue<int>("Jwt:AccessTtlMinutes", 15);

        return Ok(new TokenPairResponse
        {
            AccessToken = access,
            RefreshToken = refresh,
            ExpiresIn = ttl * 60,
        });
    }

    [HttpPost("google")]
    public async Task<IActionResult> GoogleAuth([FromBody] GoogleAuthRequest body)
    {
        var audiencesStr = _config.GetValue<string>("AppSettings:GoogleOAuthClientIds") ?? "";
        var audiences = audiencesStr.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).ToList();
        if (audiences.Count == 0)
            return StatusCode(503, new { detail = "Google Sign-In is not configured (set GOOGLE_OAUTH_CLIENT_IDS)" });

        GoogleClaims claims;
        try
        {
            claims = await _googleOAuth.VerifyIdToken(body.IdToken, audiences);
        }
        catch (InvalidOperationException ex)
        {
            return Unauthorized(new { detail = ex.Message });
        }

        if (string.IsNullOrEmpty(claims.Sub) || string.IsNullOrEmpty(claims.Email))
            return BadRequest(new { detail = "Google account has no email" });
        if (!claims.EmailVerified)
            return BadRequest(new { detail = "Google email is not verified" });

        var user = await _db.Users.FirstOrDefaultAsync(u => u.GoogleSub == claims.Sub);

        if (user != null)
        {
            if (!string.IsNullOrEmpty(claims.Name) && string.IsNullOrEmpty(user.Name))
            {
                user.Name = claims.Name.Trim();
                await _db.SaveChangesAsync();
            }
        }
        else
        {
            user = await _db.Users.FirstOrDefaultAsync(u => u.Email == claims.Email);
            if (user != null)
            {
                if (user.GoogleSub == null)
                    user.GoogleSub = claims.Sub;
                else if (user.GoogleSub != claims.Sub)
                    return Conflict(new { detail = "This email is already linked to a different sign-in method" });

                if (!string.IsNullOrEmpty(claims.Name) && string.IsNullOrEmpty(user.Name))
                    user.Name = claims.Name.Trim();
                await _db.SaveChangesAsync();
            }
            else
            {
                var uname = await AllocateGoogleUsername(claims.Email, claims.Sub);

                var superadminEmail = _config.GetValue<string>("AppSettings:SuperadminBootstrapEmail");
                var isSuper = !string.IsNullOrEmpty(superadminEmail) && claims.Email == superadminEmail.Trim().ToLowerInvariant();

                user = new User
                {
                    Email = claims.Email,
                    Username = uname,
                    PasswordHash = null,
                    Phone = null,
                    Name = claims.Name?.Trim(),
                    GoogleSub = claims.Sub,
                    IsSuperAdmin = isSuper,
                };
                _db.Users.Add(user);
                await _db.SaveChangesAsync();

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
            }
        }

        var access = _jwt.CreateAccessToken(user.Id, user.TokenVersion);
        var refresh = _jwt.CreateRefreshToken(user.Id);
        var ttl = _config.GetValue<int>("Jwt:AccessTtlMinutes", 15);

        return Ok(new TokenPairResponse
        {
            AccessToken = access,
            RefreshToken = refresh,
            ExpiresIn = ttl * 60,
        });
    }

    [HttpPost("refresh")]
    public async Task<IActionResult> Refresh([FromBody] RefreshRequest body)
    {
        var uid = _jwt.DecodeRefreshToken(body.RefreshToken);
        if (uid == null)
            return Unauthorized(new { detail = "Invalid refresh token" });

        var user = await _db.Users.FirstOrDefaultAsync(u => u.Id == uid.Value);
        if (user == null)
            return Unauthorized(new { detail = "User not found" });

        var access = _jwt.CreateAccessToken(user.Id, user.TokenVersion);
        var refresh = _jwt.CreateRefreshToken(user.Id);
        var ttl = _config.GetValue<int>("Jwt:AccessTtlMinutes", 15);

        return Ok(new TokenPairResponse
        {
            AccessToken = access,
            RefreshToken = refresh,
            ExpiresIn = ttl * 60,
        });
    }

    [HttpPost("forgot-password")]
    public async Task<IActionResult> ForgotPassword([FromBody] ForgotPasswordRequest body)
    {
        var email = body.Email.Trim().ToLowerInvariant();
        var same = new ForgotPasswordResponse
        {
            Ok = true,
            Message = "If an account exists for that email, you will receive reset instructions.",
        };

        var user = await _db.Users.FirstOrDefaultAsync(u => u.Email == email);
        if (user == null || user.PasswordHash == null)
            return Ok(same);

        var existingTokens = await _db.PasswordResetTokens.Where(t => t.UserId == user.Id).ToListAsync();
        _db.PasswordResetTokens.RemoveRange(existingTokens);

        var raw = Convert.ToHexString(RandomNumberGenerator.GetBytes(32)).ToLowerInvariant();
        var tokenHash = HashResetToken(raw);
        var exp = DateTime.UtcNow.AddHours(1);

        _db.PasswordResetTokens.Add(new PasswordResetToken
        {
            UserId = user.Id,
            TokenHash = tokenHash,
            ExpiresAt = exp,
        });
        await _db.SaveChangesAsync();

        _logger.LogInformation("Password reset token created for user_id={UserId}", user.Id);

        var env = _config.GetValue<string>("AppSettings:AppEnv", "development");
        if (env is "development" or "test")
            same.DevResetToken = raw;

        return Ok(same);
    }

    [HttpPost("reset-password")]
    public async Task<IActionResult> ResetPassword([FromBody] ResetPasswordRequest body)
    {
        var tokenHash = HashResetToken(body.Token.Trim());
        var now = DateTime.UtcNow;

        var pr = await _db.PasswordResetTokens.FirstOrDefaultAsync(t =>
            t.TokenHash == tokenHash && t.UsedAt == null && t.ExpiresAt > now);
        if (pr == null)
            return BadRequest(new { detail = "Invalid or expired reset link. Request a new one." });

        var user = await _db.Users.FirstOrDefaultAsync(u => u.Id == pr.UserId);
        if (user == null || user.PasswordHash == null)
            return BadRequest(new { detail = "This account cannot set a password here." });

        try
        {
            user.PasswordHash = _password.Hash(body.NewPassword);
        }
        catch (ArgumentException ex)
        {
            return UnprocessableEntity(new { detail = ex.Message });
        }

        pr.UsedAt = now;
        await _db.SaveChangesAsync();

        return Ok(new ResetPasswordResponse
        {
            Ok = true,
            Message = "Password updated. You can sign in now.",
        });
    }

    private static string HashResetToken(string raw)
    {
        var bytes = System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(raw));
        return Convert.ToHexString(bytes).ToLowerInvariant();
    }

    private async Task<string> AllocateGoogleUsername(string email, string sub)
    {
        var local = email.Split('@')[0].ToLowerInvariant();
        var s = Regex.Replace(local, @"[^a-z0-9_]", "_");
        s = Regex.Replace(s, @"_+", "_").Trim('_');
        var tail = Regex.Replace(sub, @"[^a-z0-9_]", "");
        tail = tail[^Math.Min(tail.Length, 8)..];
        var baseName = string.IsNullOrEmpty(s) ? $"g_{tail}" : $"{s}_{tail}";
        baseName = baseName[..Math.Min(baseName.Length, 64)];

        if (!await _db.Users.AnyAsync(u => u.Username == baseName))
            return baseName;

        var suffix = Guid.NewGuid().ToString("N")[..8];
        return $"{baseName[..Math.Min(baseName.Length - suffix.Length - 1, 64 - suffix.Length - 1)]}_{suffix}"[..Math.Min(64, 64)];
    }
}
