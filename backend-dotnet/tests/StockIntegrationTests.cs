using System.Net;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using PurchaseAssistant.Application.Features.Auth.Dtos;
using PurchaseAssistant.Application.Features.Me.Dtos;
using StockListOut = PurchaseAssistant.Application.DTOs.StockListOut;
using StockDetailOut = PurchaseAssistant.Application.DTOs.StockDetailOut;
using PurchaseAssistant.Domain.Entities.Catalog;
using PurchaseAssistant.Domain.Entities.Core;
using PurchaseAssistant.Infrastructure.Data;

namespace PurchaseAssistant.Tests;

public class StockIntegrationTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient _client;
    private readonly WebApplicationFactory<Program> _factory;

    public StockIntegrationTests(WebApplicationFactory<Program> factory)
    {
        Environment.SetEnvironmentVariable("UseInMemoryDatabase", "true");
        Environment.SetEnvironmentVariable("Jwt__Secret", "test-secret-key-min-32-chars-long!!");
        Environment.SetEnvironmentVariable("Jwt__RefreshSecret", "test-refresh-secret-key-min-32-chars!!");
        Environment.SetEnvironmentVariable("Jwt__AccessTtlMinutes", "15");
        Environment.SetEnvironmentVariable("Jwt__RefreshTtlDays", "30");
        Environment.SetEnvironmentVariable("AppSettings__AppEnv", "test");
        Environment.SetEnvironmentVariable("AppSettings__AllowPublicRegistration", "true");
        Environment.SetEnvironmentVariable("AppSettings__GoogleOAuthClientIds", "");

        _factory = factory;
        _client = _factory.CreateClient();
    }

    private IServiceScopeFactory GetScopeFactory()
        => _factory.Services.GetRequiredService<IServiceScopeFactory>();

    private async Task<string?> SetupAuth(string email)
    {
        var scopeFactory = GetScopeFactory();
        using var scope = scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<PurchaseAssistantDbContext>();

        var existing = await db.Users.FirstOrDefaultAsync(u => u.Email == email);
        if (existing == null)
        {
            var hash = BCrypt.Net.BCrypt.HashPassword("Test1234!", workFactor: 12);
            var user = new User
            {
                Email = email,
                Username = email.Split('@')[0],
                PasswordHash = hash,
                Name = email.Split('@')[0],
                IsActive = true,
                TokenVersion = 0,
            };
            db.Users.Add(user);
            await db.SaveChangesAsync();

            var biz = new Business { Name = "Test Business" };
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

        var login = await _client.PostAsJsonAsync("/v1/auth/login", new
        {
            email,
            password = "Test1234!"
        });
        if (login.StatusCode != HttpStatusCode.OK) return null;
        var res = await login.Content.ReadFromJsonAsync<TokenPairResponse>();
        return res?.AccessToken;
    }

    private async Task<Guid> GetBusinessId()
    {
        var res = await _client.GetAsync("/v1/me/businesses");
        res.EnsureSuccessStatusCode();
        var bizList = await res.Content.ReadFromJsonAsync<List<BusinessBriefResponse>>();
        Assert.NotNull(bizList);
        return bizList.First().Id;
    }

    [Fact]
    public async Task GetStockList_ReturnsItems()
    {
        var token = await SetupAuth("stock-list@test.com");
        Assert.NotNull(token);
        _client.DefaultRequestHeaders.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token);
        var bizId = await GetBusinessId();

        var scopeFactory = GetScopeFactory();
        using var scope = scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<PurchaseAssistantDbContext>();

        var cat = new ItemCategory { BusinessId = bizId, Name = "Grains" };
        db.ItemCategories.Add(cat);
        await db.SaveChangesAsync();

        var type = new CategoryType { CategoryId = cat.Id, Name = "Rice" };
        db.CategoryTypes.Add(type);
        await db.SaveChangesAsync();

        var item = new CatalogItem
        {
            BusinessId = bizId, CategoryId = cat.Id, TypeId = type.Id,
            Name = "Basmati Rice", NormalizedName = "basmati rice", DefaultUnit = "kg",
            CurrentStock = 100, ReorderLevel = 20, StockVersion = 1,
        };
        db.CatalogItems.Add(item);
        await db.SaveChangesAsync();

        var res = await _client.GetAsync($"/v1/businesses/{bizId}/stock/list");
        Assert.Equal(HttpStatusCode.OK, res.StatusCode);
        var body = await res.Content.ReadFromJsonAsync<StockListOut>();
        Assert.NotNull(body);
        Assert.NotEmpty(body.Items);
        Assert.Contains(body.Items, i => i.Name == "Basmati Rice");
    }

    [Fact]
    public async Task PatchStock_Success()
    {
        var token = await SetupAuth("stock-patch@test.com");
        Assert.NotNull(token);
        _client.DefaultRequestHeaders.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token);
        var bizId = await GetBusinessId();

        var scopeFactory = GetScopeFactory();
        using var scope = scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<PurchaseAssistantDbContext>();

        var cat = new ItemCategory { BusinessId = bizId, Name = "Spices" };
        db.ItemCategories.Add(cat);
        await db.SaveChangesAsync();

        var item = new CatalogItem
        {
            BusinessId = bizId, CategoryId = cat.Id, Name = "Turmeric",
            NormalizedName = "turmeric", DefaultUnit = "kg",
            CurrentStock = 50, ReorderLevel = 10, StockVersion = 1,
        };
        db.CatalogItems.Add(item);
        await db.SaveChangesAsync();

        var res = await _client.PatchAsJsonAsync(
            $"/v1/businesses/{bizId}/stock/{item.Id}",
            new
            {
                newQty = 75m,
                adjustmentType = "verification",
                reason = "Manual count",
                lastSeenStockVersion = 1,
            });
        Assert.Equal(HttpStatusCode.OK, res.StatusCode);
        var updated = await res.Content.ReadFromJsonAsync<StockDetailOut>();
        Assert.NotNull(updated);
        Assert.Equal(75, updated.CurrentStock);
        Assert.Equal(2, updated.StockVersion);
    }

    [Fact]
    public async Task PatchStock_VersionConflict_Returns409()
    {
        var token = await SetupAuth("stock-conflict@test.com");
        Assert.NotNull(token);
        _client.DefaultRequestHeaders.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token);
        var bizId = await GetBusinessId();

        var scopeFactory = GetScopeFactory();
        using var scope = scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<PurchaseAssistantDbContext>();

        var cat = new ItemCategory { BusinessId = bizId, Name = "Spices" };
        db.ItemCategories.Add(cat);
        await db.SaveChangesAsync();

        var item = new CatalogItem
        {
            BusinessId = bizId, CategoryId = cat.Id, Name = "Cinnamon",
            NormalizedName = "cinnamon", DefaultUnit = "kg",
            CurrentStock = 30, ReorderLevel = 5, StockVersion = 3,
        };
        db.CatalogItems.Add(item);
        await db.SaveChangesAsync();

        var res = await _client.PatchAsJsonAsync(
            $"/v1/businesses/{bizId}/stock/{item.Id}",
            new
            {
                newQty = 10m,
                adjustmentType = "verification",
                lastSeenStockVersion = 1,
            });
        Assert.Equal(HttpStatusCode.Conflict, res.StatusCode);
        var body = await res.Content.ReadFromJsonAsync<Dictionary<string, object>>();
        Assert.NotNull(body);
        Assert.Contains("code", body.Keys);
        Assert.Equal("STALE_STOCK_VERSION_CONFLICT", body["code"]?.ToString());
    }
}
