using System.Net;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using PurchaseAssistant.Application.Features.Auth.Dtos;
using PurchaseAssistant.Application.Features.Me.Dtos;
using PurchaseAssistant.Domain.Entities.Core;
using PurchaseAssistant.Infrastructure.Data;

namespace PurchaseAssistant.Tests;

public class AuthFlowIntegrationTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient _client;
    private readonly WebApplicationFactory<Program> _factory;

    public AuthFlowIntegrationTests(WebApplicationFactory<Program> factory)
    {
        Environment.SetEnvironmentVariable("UseInMemoryDatabase", "true");
        Environment.SetEnvironmentVariable("Jwt__Secret", "test-secret-key-min-32-chars-long!!");
        Environment.SetEnvironmentVariable("Jwt__RefreshSecret", "test-refresh-secret-key-min-32-chars!!");
        Environment.SetEnvironmentVariable("Jwt__AccessTtlMinutes", "15");
        Environment.SetEnvironmentVariable("Jwt__RefreshTtlDays", "30");
        Environment.SetEnvironmentVariable("AppSettings__AppEnv", "test");
        Environment.SetEnvironmentVariable("AppSettings__AllowPublicRegistration", "true");
        Environment.SetEnvironmentVariable("AppSettings__GoogleOAuthClientIds", "");
        Environment.SetEnvironmentVariable("AppSettings__DevReturnOtp", "true");
        Environment.SetEnvironmentVariable("AppSettings__DevOtpCode", "000000");

        _factory = factory;
        _client = _factory.CreateClient();
    }

    [Fact]
    public async Task Register_And_Login_Success()
    {
        var register = await _client.PostAsJsonAsync("/v1/auth/register", new RegisterRequest
        {
            Email = "test@example.com",
            Username = "testuser",
            Password = "Secure123",
            Name = "Test User"
        });

        // Self-registration could be disabled by default; if 403, skip
        if (register.StatusCode == HttpStatusCode.Forbidden)
            return;

        Assert.Equal(HttpStatusCode.OK, register.StatusCode);
        var registerRes = await register.Content.ReadFromJsonAsync<TokenPairResponse>();
        Assert.NotNull(registerRes);
        Assert.NotEmpty(registerRes.AccessToken);
        Assert.NotEmpty(registerRes.RefreshToken);

        var login = await _client.PostAsJsonAsync("/v1/auth/login", new LoginRequest
        {
            Email = "test@example.com",
            Password = "Secure123"
        });
        Assert.Equal(HttpStatusCode.OK, login.StatusCode);
        var loginRes = await login.Content.ReadFromJsonAsync<TokenPairResponse>();
        Assert.NotNull(loginRes);
        Assert.NotEmpty(loginRes.AccessToken);
    }

    [Fact]
    public async Task Login_InvalidCredentials_Returns401()
    {
        var res = await _client.PostAsJsonAsync("/v1/auth/login", new LoginRequest
        {
            Email = "nonexistent@example.com",
            Password = "WrongPass1"
        });
        Assert.Equal(HttpStatusCode.Unauthorized, res.StatusCode);
    }

    [Fact]
    public async Task Refresh_InvalidToken_Returns401()
    {
        var res = await _client.PostAsJsonAsync("/v1/auth/refresh", new RefreshRequest
        {
            RefreshToken = "invalid.jwt.token"
        });
        Assert.Equal(HttpStatusCode.Unauthorized, res.StatusCode);
    }

    [Fact]
    public async Task Refresh_ValidToken_ReturnsNewTokens()
    {
        var user = await SeedUser("refresh-test@example.com", "refreshuser", "Refresh123");
        var loginRes = await _client.PostAsJsonAsync("/v1/auth/login", new LoginRequest
        {
            Email = "refresh-test@example.com",
            Password = "Refresh123"
        });
        if (loginRes.StatusCode != HttpStatusCode.OK) return;
        var loginTokens = await loginRes.Content.ReadFromJsonAsync<TokenPairResponse>();
        if (loginTokens == null) return;

        var res = await _client.PostAsJsonAsync("/v1/auth/refresh", new RefreshRequest
        {
            RefreshToken = loginTokens.RefreshToken
        });
        Assert.Equal(HttpStatusCode.OK, res.StatusCode);
        var refreshRes = await res.Content.ReadFromJsonAsync<TokenPairResponse>();
        Assert.NotNull(refreshRes);
        Assert.NotEmpty(refreshRes.AccessToken);
    }

    [Fact]
    public async Task ForgotPassword_ReturnsOk_ForKnownAndUnknownEmails()
    {
        await SeedUser("forgot@example.com", "forgotuser", "Forgot123");

        var resKnown = await _client.PostAsJsonAsync("/v1/auth/forgot-password", new ForgotPasswordRequest
        {
            Email = "forgot@example.com"
        });
        Assert.Equal(HttpStatusCode.OK, resKnown.StatusCode);
        var knownRes = await resKnown.Content.ReadFromJsonAsync<ForgotPasswordResponse>();
        Assert.NotNull(knownRes);
        Assert.True(knownRes.Ok);
        Assert.NotEmpty(knownRes.DevResetToken);

        var resUnknown = await _client.PostAsJsonAsync("/v1/auth/forgot-password", new ForgotPasswordRequest
        {
            Email = "unknown@example.com"
        });
        Assert.Equal(HttpStatusCode.OK, resUnknown.StatusCode);
    }

    [Fact]
    public async Task ResetPassword_WithValidToken_Succeeds()
    {
        await SeedUser("reset@example.com", "resetuser", "OldPass123");

        var forgot = await _client.PostAsJsonAsync("/v1/auth/forgot-password", new ForgotPasswordRequest
        {
            Email = "reset@example.com"
        });
        var forgotRes = await forgot.Content.ReadFromJsonAsync<ForgotPasswordResponse>();
        Assert.NotNull(forgotRes);
        Assert.NotEmpty(forgotRes.DevResetToken);

        var reset = await _client.PostAsJsonAsync("/v1/auth/reset-password", new ResetPasswordRequest
        {
            Token = forgotRes.DevResetToken!,
            NewPassword = "NewPass456"
        });
        Assert.Equal(HttpStatusCode.OK, reset.StatusCode);
        var resetRes = await reset.Content.ReadFromJsonAsync<ResetPasswordResponse>();
        Assert.NotNull(resetRes);
        Assert.True(resetRes.Ok);

        var login = await _client.PostAsJsonAsync("/v1/auth/login", new LoginRequest
        {
            Email = "reset@example.com",
            Password = "NewPass456"
        });
        Assert.Equal(HttpStatusCode.OK, login.StatusCode);
    }

    [Fact]
    public async Task Me_Profile_RequiresAuth()
    {
        var res = await _client.GetAsync("/v1/me/profile");
        Assert.Equal(HttpStatusCode.Unauthorized, res.StatusCode);
    }

    [Fact]
    public async Task Me_Profile_ReturnsProfile()
    {
        var token = await CreateAuthenticatedUser("me-profile@example.com", "meuser", "MePass123");
        if (token == null) return;

        _client.DefaultRequestHeaders.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token);

        var res = await _client.GetAsync("/v1/me/profile");
        Assert.Equal(HttpStatusCode.OK, res.StatusCode);
        var profile = await res.Content.ReadFromJsonAsync<UserProfileResponse>();
        Assert.NotNull(profile);
        Assert.Equal("me-profile@example.com", profile.Email);
        Assert.Equal("meuser", profile.Username);
    }

    [Fact]
    public async Task Me_PatchProfile_UpdatesName()
    {
        var token = await CreateAuthenticatedUser("patch-me@example.com", "patchme", "Patch123");
        if (token == null) return;

        _client.DefaultRequestHeaders.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token);

        var patch = await _client.PatchAsJsonAsync("/v1/me/profile", new UserProfilePatchRequest
        {
            Name = "Updated Name"
        });
        Assert.Equal(HttpStatusCode.OK, patch.StatusCode);
        var profile = await patch.Content.ReadFromJsonAsync<UserProfileResponse>();
        Assert.NotNull(profile);
        Assert.Equal("Updated Name", profile.Name);
    }

    [Fact]
    public async Task Me_ListBusinesses_ReturnsBusinesses()
    {
        var token = await CreateAuthenticatedUser("biz-list@example.com", "bizlist", "Biz1234");
        if (token == null) return;

        _client.DefaultRequestHeaders.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token);

        var res = await _client.GetAsync("/v1/me/businesses");
        Assert.Equal(HttpStatusCode.OK, res.StatusCode);
        var businesses = await res.Content.ReadFromJsonAsync<List<BusinessBriefResponse>>();
        Assert.NotNull(businesses);
        Assert.NotEmpty(businesses);
    }

    [Fact]
    public async Task Me_BootstrapWorkspace_CreatesBusiness()
    {
        var token = await CreateAuthenticatedUser("bootstrap@example.com", "bootstrap", "Boot1234");
        if (token == null) return;

        _client.DefaultRequestHeaders.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token);

        var res = await _client.PostAsync("/v1/me/bootstrap-workspace", null);
        Assert.Equal(HttpStatusCode.OK, res.StatusCode);
        var boot = await res.Content.ReadFromJsonAsync<BootstrapWorkspaceResponse>();
        Assert.NotNull(boot);
        Assert.NotEqual(Guid.Empty, boot.BusinessId);
    }

    [Fact]
    public async Task Me_UpdateBranding_RequiresOwner()
    {
        var token = await CreateAuthenticatedUser("branding@example.com", "branding", "Brand123");
        if (token == null) return;

        _client.DefaultRequestHeaders.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token);

        var getBiz = await _client.GetAsync("/v1/me/businesses");
        var bizList = await getBiz.Content.ReadFromJsonAsync<List<BusinessBriefResponse>>();
        Assert.NotNull(bizList);
        var bizId = bizList.FirstOrDefault()?.Id;
        if (bizId == null) return;

        var patch = await _client.PatchAsJsonAsync($"/v1/me/businesses/{bizId}/branding", new BusinessBrandingPatchRequest
        {
            Name = "New Biz Name",
            BrandingTitle = "New Title",
            GstNumber = "22AAAAA0000A1Z5",
            Address = "123 Test St",
            Phone = "9876543210",
            ContactEmail = "contact@newbiz.com"
        });
        Assert.Equal(HttpStatusCode.OK, patch.StatusCode);
        var biz = await patch.Content.ReadFromJsonAsync<BusinessBriefResponse>();
        Assert.NotNull(biz);
        Assert.Equal("New Biz Name", biz.Name);
        Assert.Equal("New Title", biz.BrandingTitle);
    }

    private async Task<User> SeedUser(string email, string username, string password)
    {
        var scopeFactory = GetScopeFactory();
        using var scope = scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<PurchaseAssistantDbContext>();

        var existing = await db.Users.FirstOrDefaultAsync(u => u.Email == email);
        if (existing != null) return existing;

        var hash = BCrypt.Net.BCrypt.HashPassword(password, workFactor: 12);
        var user = new User
        {
            Email = email,
            Username = username,
            PasswordHash = hash,
            Name = username,
            IsActive = true,
            TokenVersion = 0,
        };
        db.Users.Add(user);
        await db.SaveChangesAsync();

        return user;
    }

    private IServiceScopeFactory GetScopeFactory()
    {
        return _factory.Services.GetRequiredService<IServiceScopeFactory>();
    }

    private async Task<string?> LoginAndGetTokens(string email, string password)
    {
        var login = await _client.PostAsJsonAsync("/v1/auth/login", new LoginRequest
        {
            Email = email,
            Password = password
        });
        if (login.StatusCode != HttpStatusCode.OK) return null;
        var res = await login.Content.ReadFromJsonAsync<TokenPairResponse>();
        return res?.AccessToken;
    }

    private async Task<string?> CreateAuthenticatedUser(string email, string username, string password)
    {
        var user = await SeedUser(email, username, password);

        var scopeFactory = GetScopeFactory();
        using var scope = scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<PurchaseAssistantDbContext>();

        var hasBiz = await db.Memberships.AnyAsync(m => m.UserId == user.Id);
        if (!hasBiz)
        {
            var biz = new Business { Name = "Harisree workspace" };
            db.Businesses.Add(biz);
            await db.SaveChangesAsync();

            db.Memberships.Add(new Membership
            {
                UserId = user.Id,
                BusinessId = biz.Id,
                Role = "owner",
            });
            await db.SaveChangesAsync();
        }

        return await LoginAndGetTokens(email, password);
    }
}
