using System.Net;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using PurchaseAssistant.Application.DTOs.Catalog;
using PurchaseAssistant.Application.Features.Auth.Dtos;
using PurchaseAssistant.Application.Features.Me.Dtos;
using PurchaseAssistant.Domain.Entities.Catalog;
using PurchaseAssistant.Domain.Entities.Contacts;
using PurchaseAssistant.Domain.Entities.Core;
using PurchaseAssistant.Infrastructure.Data;

namespace PurchaseAssistant.Tests;

public class CatalogIntegrationTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient _client;
    private readonly WebApplicationFactory<Program> _factory;

    public CatalogIntegrationTests(WebApplicationFactory<Program> factory)
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

    // ==================== Helper methods ====================

    private IServiceScopeFactory GetScopeFactory()
        => _factory.Services.GetRequiredService<IServiceScopeFactory>();

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

    private async Task<string?> LoginAndGetTokens(string email, string password)
    {
        var login = await _client.PostAsJsonAsync("/v1/auth/login", new
        {
            email,
            password
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

        return await LoginAndGetTokens(email, password);
    }

    private async Task<Guid> GetBusinessId()
    {
        var res = await _client.GetAsync("/v1/me/businesses");
        res.EnsureSuccessStatusCode();
        var bizList = await res.Content.ReadFromJsonAsync<List<BusinessBriefResponse>>();
        Assert.NotNull(bizList);
        return bizList.First().Id;
    }

    private async Task SetupAuth(string email)
    {
        var token = await CreateAuthenticatedUser(email, email.Split('@')[0], "Test1234!");
        Assert.NotNull(token);
        _client.DefaultRequestHeaders.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", token);
    }

    // ==================== Category Tests ====================

    [Fact]
    public async Task Categories_CreateAndList_Success()
    {
        await SetupAuth("cat-list@test.com");
        var bizId = await GetBusinessId();

        var create = await _client.PostAsJsonAsync(
            $"/v1/businesses/{bizId}/item-categories",
            new ItemCategoryCreateRequest { Name = "Vegetables" });
        Assert.Equal(HttpStatusCode.Created, create.StatusCode);
        var created = await create.Content.ReadFromJsonAsync<ItemCategoryOut>();
        Assert.NotNull(created);
        Assert.Equal("Vegetables", created.Name);

        var list = await _client.GetAsync($"/v1/businesses/{bizId}/item-categories");
        Assert.Equal(HttpStatusCode.OK, list.StatusCode);
        var cats = await list.Content.ReadFromJsonAsync<List<ItemCategoryOut>>();
        Assert.NotNull(cats);
        Assert.Single(cats);
        Assert.Equal("Vegetables", cats[0].Name);
    }

    [Fact]
    public async Task Categories_GetById_Success()
    {
        await SetupAuth("cat-get@test.com");
        var bizId = await GetBusinessId();

        var scopeFactory = GetScopeFactory();
        using var scope = scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<PurchaseAssistantDbContext>();
        var cat = new ItemCategory { BusinessId = bizId, Name = "Fruits" };
        db.ItemCategories.Add(cat);
        await db.SaveChangesAsync();

        var res = await _client.GetAsync($"/v1/businesses/{bizId}/item-categories/{cat.Id}");
        Assert.Equal(HttpStatusCode.OK, res.StatusCode);
        var outCat = await res.Content.ReadFromJsonAsync<ItemCategoryOut>();
        Assert.NotNull(outCat);
        Assert.Equal("Fruits", outCat.Name);
    }

    [Fact]
    public async Task Categories_Update_Success()
    {
        await SetupAuth("cat-upd@test.com");
        var bizId = await GetBusinessId();

        var scopeFactory = GetScopeFactory();
        using var scope = scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<PurchaseAssistantDbContext>();
        var cat = new ItemCategory { BusinessId = bizId, Name = "Old Name" };
        db.ItemCategories.Add(cat);
        await db.SaveChangesAsync();

        var res = await _client.PatchAsJsonAsync(
            $"/v1/businesses/{bizId}/item-categories/{cat.Id}",
            new ItemCategoryUpdateRequest { Name = "Updated Name" });
        Assert.Equal(HttpStatusCode.OK, res.StatusCode);
        var updated = await res.Content.ReadFromJsonAsync<ItemCategoryOut>();
        Assert.NotNull(updated);
        Assert.Equal("Updated Name", updated.Name);
    }

    [Fact]
    public async Task Categories_Delete_Success()
    {
        await SetupAuth("cat-del@test.com");
        var bizId = await GetBusinessId();

        var scopeFactory = GetScopeFactory();
        using var scope = scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<PurchaseAssistantDbContext>();
        var cat = new ItemCategory { BusinessId = bizId, Name = "To Delete" };
        db.ItemCategories.Add(cat);
        await db.SaveChangesAsync();

        var res = await _client.DeleteAsync($"/v1/businesses/{bizId}/item-categories/{cat.Id}");
        Assert.Equal(HttpStatusCode.NoContent, res.StatusCode);

        using var verifyScope = GetScopeFactory().CreateScope();
        var verifyDb = verifyScope.ServiceProvider.GetRequiredService<PurchaseAssistantDbContext>();
        var deleted = await verifyDb.ItemCategories.FindAsync(cat.Id);
        Assert.Null(deleted);
    }

    // ==================== Category Type Tests ====================

    [Fact]
    public async Task CategoryTypes_CreateAndList_Success()
    {
        await SetupAuth("ct-list@test.com");
        var bizId = await GetBusinessId();

        var scopeFactory = GetScopeFactory();
        using var scope = scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<PurchaseAssistantDbContext>();
        var cat = new ItemCategory { BusinessId = bizId, Name = "Category" };
        db.ItemCategories.Add(cat);
        await db.SaveChangesAsync();

        var create = await _client.PostAsJsonAsync(
            $"/v1/businesses/{bizId}/item-categories/{cat.Id}/category-types",
            new CategoryTypeCreateRequest { Name = "Type A" });
        Assert.Equal(HttpStatusCode.Created, create.StatusCode);
        var created = await create.Content.ReadFromJsonAsync<CategoryTypeOut>();
        Assert.NotNull(created);
        Assert.Equal("Type A", created.Name);
        Assert.Equal(cat.Id, created.CategoryId);

        var list = await _client.GetAsync(
            $"/v1/businesses/{bizId}/item-categories/{cat.Id}/category-types");
        Assert.Equal(HttpStatusCode.OK, list.StatusCode);
        var types = await list.Content.ReadFromJsonAsync<List<CategoryTypeOut>>();
        Assert.NotNull(types);
        Assert.Single(types);
    }

    [Fact]
    public async Task CategoryTypes_UpdateAndDelete_Success()
    {
        await SetupAuth("ct-upd@test.com");
        var bizId = await GetBusinessId();

        var scopeFactory = GetScopeFactory();
        using var scope = scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<PurchaseAssistantDbContext>();
        var cat = new ItemCategory { BusinessId = bizId, Name = "Cat" };
        db.ItemCategories.Add(cat);
        await db.SaveChangesAsync();
        var type = new CategoryType { CategoryId = cat.Id, Name = "Old Type" };
        db.CategoryTypes.Add(type);
        await db.SaveChangesAsync();

        var upd = await _client.PatchAsJsonAsync(
            $"/v1/businesses/{bizId}/item-categories/{cat.Id}/category-types/{type.Id}",
            new CategoryTypeUpdateRequest { Name = "New Type" });
        Assert.Equal(HttpStatusCode.OK, upd.StatusCode);
        var updated = await upd.Content.ReadFromJsonAsync<CategoryTypeOut>();
        Assert.NotNull(updated);
        Assert.Equal("New Type", updated.Name);

        var del = await _client.DeleteAsync(
            $"/v1/businesses/{bizId}/item-categories/{cat.Id}/category-types/{type.Id}");
        Assert.Equal(HttpStatusCode.NoContent, del.StatusCode);
    }

    [Fact]
    public async Task CategoryTypesIndex_Success()
    {
        await SetupAuth("ct-idx@test.com");
        var bizId = await GetBusinessId();

        var scopeFactory = GetScopeFactory();
        using var scope = scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<PurchaseAssistantDbContext>();
        var cat = new ItemCategory { BusinessId = bizId, Name = "Cat1" };
        db.ItemCategories.Add(cat);
        await db.SaveChangesAsync();
        db.CategoryTypes.Add(new CategoryType { CategoryId = cat.Id, Name = "Type1" });
        db.CategoryTypes.Add(new CategoryType { CategoryId = cat.Id, Name = "Type2" });
        await db.SaveChangesAsync();

        var res = await _client.GetAsync($"/v1/businesses/{bizId}/category-types-index");
        Assert.Equal(HttpStatusCode.OK, res.StatusCode);
        var idx = await res.Content.ReadFromJsonAsync<List<CategoryTypeIndexOut>>();
        Assert.NotNull(idx);
        Assert.Equal(2, idx.Count);
        Assert.All(idx, t => Assert.Equal("Cat1", t.CategoryName));
    }

    // ==================== Catalog Item Tests ====================

    [Fact]
    public async Task CatalogItems_CreateAndList_Success()
    {
        await SetupAuth("item-list@test.com");
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

        var create = await _client.PostAsJsonAsync(
            $"/v1/businesses/{bizId}/catalog-items",
            new CatalogItemCreateRequest
            {
                CategoryId = cat.Id,
                TypeId = type.Id,
                Name = "Basmati Rice",
                DefaultUnit = "kg",
            });
        Assert.Equal(HttpStatusCode.Created, create.StatusCode);
        var created = await create.Content.ReadFromJsonAsync<CatalogItemOut>();
        Assert.NotNull(created);
        Assert.Equal("Basmati Rice", created.Name);
        Assert.Equal("kg", created.DefaultUnit);

        var list = await _client.GetAsync(
            $"/v1/businesses/{bizId}/catalog-items?categoryId={cat.Id}");
        Assert.Equal(HttpStatusCode.OK, list.StatusCode);
        var items = await list.Content.ReadFromJsonAsync<List<CatalogItemOut>>();
        Assert.NotNull(items);
        Assert.NotEmpty(items);
        Assert.Contains(items, i => i.Name == "Basmati Rice");
    }

    [Fact]
    public async Task CatalogItems_GetById_Success()
    {
        await SetupAuth("item-get@test.com");
        var bizId = await GetBusinessId();

        var scopeFactory = GetScopeFactory();
        using var scope = scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<PurchaseAssistantDbContext>();
        var cat = new ItemCategory { BusinessId = bizId, Name = "Cat" };
        db.ItemCategories.Add(cat);
        await db.SaveChangesAsync();
        var item = new CatalogItem
        {
            BusinessId = bizId, CategoryId = cat.Id, Name = "Test Item",
            DefaultUnit = "kg", NormalizedName = "test item",
        };
        db.CatalogItems.Add(item);
        await db.SaveChangesAsync();

        var res = await _client.GetAsync(
            $"/v1/businesses/{bizId}/catalog-items/{item.Id}");
        Assert.Equal(HttpStatusCode.OK, res.StatusCode);
        var outItem = await res.Content.ReadFromJsonAsync<CatalogItemOut>();
        Assert.NotNull(outItem);
        Assert.Equal("Test Item", outItem.Name);
    }

    [Fact]
    public async Task CatalogItems_Update_Success()
    {
        await SetupAuth("item-upd@test.com");
        var bizId = await GetBusinessId();

        var scopeFactory = GetScopeFactory();
        using var scope = scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<PurchaseAssistantDbContext>();
        var cat = new ItemCategory { BusinessId = bizId, Name = "Cat" };
        db.ItemCategories.Add(cat);
        await db.SaveChangesAsync();
        var item = new CatalogItem
        {
            BusinessId = bizId, CategoryId = cat.Id, Name = "Old Name",
            DefaultUnit = "kg", NormalizedName = "old name",
        };
        db.CatalogItems.Add(item);
        await db.SaveChangesAsync();

        var res = await _client.PatchAsJsonAsync(
            $"/v1/businesses/{bizId}/catalog-items/{item.Id}",
            new CatalogItemUpdateRequest
            {
                Name = "Updated Name",
                DefaultLandingCost = 50.0,
                DefaultSellingCost = 60.0,
            });
        Assert.Equal(HttpStatusCode.OK, res.StatusCode);
        var updated = await res.Content.ReadFromJsonAsync<CatalogItemOut>();
        Assert.NotNull(updated);
        Assert.Equal("Updated Name", updated.Name);
        Assert.Equal(50.0, updated.DefaultLandingCost);
    }

    [Fact]
    public async Task CatalogItems_Delete_SoftDeletes()
    {
        await SetupAuth("item-del@test.com");
        var bizId = await GetBusinessId();

        var scopeFactory = GetScopeFactory();
        using var scope = scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<PurchaseAssistantDbContext>();
        var cat = new ItemCategory { BusinessId = bizId, Name = "Cat" };
        db.ItemCategories.Add(cat);
        await db.SaveChangesAsync();
        var item = new CatalogItem
        {
            BusinessId = bizId, CategoryId = cat.Id, Name = "To Delete",
            DefaultUnit = "kg", NormalizedName = "to delete",
        };
        db.CatalogItems.Add(item);
        await db.SaveChangesAsync();

        var res = await _client.DeleteAsync(
            $"/v1/businesses/{bizId}/catalog-items/{item.Id}");
        Assert.Equal(HttpStatusCode.NoContent, res.StatusCode);

        using var verifyScope = GetScopeFactory().CreateScope();
        var verifyDb = verifyScope.ServiceProvider.GetRequiredService<PurchaseAssistantDbContext>();
        var dbItem = await verifyDb.CatalogItems.FindAsync(item.Id);
        Assert.Null(dbItem);
    }

    [Fact]
    public async Task CatalogItems_CreateWithSupplierDefaults_Success()
    {
        await SetupAuth("item-sup@test.com");
        var bizId = await GetBusinessId();

        var scopeFactory = GetScopeFactory();
        using var scope = scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<PurchaseAssistantDbContext>();

        var cat = new ItemCategory { BusinessId = bizId, Name = "Spices" };
        db.ItemCategories.Add(cat);
        await db.SaveChangesAsync();

        var supplier = new Supplier { BusinessId = bizId, Name = "Supplier A" };
        db.Suppliers.Add(supplier);
        await db.SaveChangesAsync();

        var broker = new Broker { BusinessId = bizId, Name = "Broker A" };
        db.Brokers.Add(broker);
        await db.SaveChangesAsync();

        var create = await _client.PostAsJsonAsync(
            $"/v1/businesses/{bizId}/catalog-items",
            new CatalogItemCreateRequest
            {
                CategoryId = cat.Id,
                Name = "Turmeric Powder",
                DefaultUnit = "kg",
                DefaultSupplierIds = new List<Guid> { supplier.Id },
                DefaultBrokerIds = new List<Guid> { broker.Id },
            });
        Assert.Equal(HttpStatusCode.Created, create.StatusCode);
        var created = await create.Content.ReadFromJsonAsync<CatalogItemOut>();
        Assert.NotNull(created);
        Assert.Equal("Turmeric Powder", created.Name);
        Assert.Contains(supplier.Id, created.DefaultSupplierIds);
        Assert.Contains(broker.Id, created.DefaultBrokerIds);
    }

    [Fact]
    public async Task CatalogItems_FromScan_Success()
    {
        await SetupAuth("item-scan@test.com");
        var bizId = await GetBusinessId();

        var scopeFactory = GetScopeFactory();
        using var scope = scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<PurchaseAssistantDbContext>();
        var cat = new ItemCategory { BusinessId = bizId, Name = "Cat" };
        db.ItemCategories.Add(cat);
        await db.SaveChangesAsync();
        var type = new CategoryType { CategoryId = cat.Id, Name = "Type" };
        db.CategoryTypes.Add(type);
        await db.SaveChangesAsync();

        var create = await _client.PostAsJsonAsync(
            $"/v1/businesses/{bizId}/catalog-items/from-scan",
            new CatalogItemFromScanRequest
            {
                Barcode = "8901234567890",
                ItemCode = "ITEM001",
                Name = "Scanned Item",
                TypeId = type.Id,
                DefaultUnit = "kg",
            });
        Assert.Equal(HttpStatusCode.Created, create.StatusCode);
        var created = await create.Content.ReadFromJsonAsync<CatalogItemOut>();
        Assert.NotNull(created);
        Assert.Equal("Scanned Item", created.Name);
        Assert.Equal("8901234567890", created.Barcode);
        Assert.Equal("ITEM001", created.ItemCode);
    }

    [Fact]
    public async Task CatalogItems_ItemCodeGeneration_Success()
    {
        await SetupAuth("item-codegen@test.com");
        var bizId = await GetBusinessId();

        var scopeFactory = GetScopeFactory();
        using var scope = scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<PurchaseAssistantDbContext>();
        var cat = new ItemCategory { BusinessId = bizId, Name = "Cat" };
        db.ItemCategories.Add(cat);
        await db.SaveChangesAsync();
        var item = new CatalogItem
        {
            BusinessId = bizId, CategoryId = cat.Id, Name = "Gen Item",
            DefaultUnit = "kg", NormalizedName = "gen item",
        };
        db.CatalogItems.Add(item);
        await db.SaveChangesAsync();

        var res = await _client.PostAsync(
            $"/v1/businesses/{bizId}/catalog-items/{item.Id}/generate-code", null);
        Assert.Equal(HttpStatusCode.OK, res.StatusCode);
        var outItem = await res.Content.ReadFromJsonAsync<CatalogItemOut>();
        Assert.NotNull(outItem);
        Assert.NotNull(outItem.ItemCode);
    }

    // ==================== Variant Tests ====================

    [Fact]
    public async Task Variants_CreateAndList_Success()
    {
        await SetupAuth("var-list@test.com");
        var bizId = await GetBusinessId();

        var scopeFactory = GetScopeFactory();
        using var scope = scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<PurchaseAssistantDbContext>();
        var cat = new ItemCategory { BusinessId = bizId, Name = "Cat" };
        db.ItemCategories.Add(cat);
        await db.SaveChangesAsync();
        var item = new CatalogItem
        {
            BusinessId = bizId, CategoryId = cat.Id, Name = "Base Item",
            DefaultUnit = "kg", NormalizedName = "base item",
        };
        db.CatalogItems.Add(item);
        await db.SaveChangesAsync();

        var create = await _client.PostAsJsonAsync(
            $"/v1/businesses/{bizId}/catalog-items/{item.Id}/variants",
            new CatalogVariantCreateRequest { Name = "Variant A", DefaultKgPerBag = 25 });
        Assert.Equal(HttpStatusCode.Created, create.StatusCode);
        var created = await create.Content.ReadFromJsonAsync<CatalogVariantOut>();
        Assert.NotNull(created);
        Assert.Equal("Variant A", created.Name);
        Assert.Equal(25, created.DefaultKgPerBag);

        var list = await _client.GetAsync(
            $"/v1/businesses/{bizId}/catalog-items/{item.Id}/variants");
        Assert.Equal(HttpStatusCode.OK, list.StatusCode);
        var vars = await list.Content.ReadFromJsonAsync<List<CatalogVariantOut>>();
        Assert.NotNull(vars);
        Assert.Single(vars);
    }

    [Fact]
    public async Task Variants_UpdateAndDelete_Success()
    {
        await SetupAuth("var-upd@test.com");
        var bizId = await GetBusinessId();

        var scopeFactory = GetScopeFactory();
        using var scope = scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<PurchaseAssistantDbContext>();
        var cat = new ItemCategory { BusinessId = bizId, Name = "Cat" };
        db.ItemCategories.Add(cat);
        await db.SaveChangesAsync();
        var item = new CatalogItem
        {
            BusinessId = bizId, CategoryId = cat.Id, Name = "Item",
            DefaultUnit = "kg", NormalizedName = "item",
        };
        db.CatalogItems.Add(item);
        await db.SaveChangesAsync();
        var variant = new CatalogVariant
        {
            BusinessId = bizId, CatalogItemId = item.Id, Name = "Old Var",
        };
        db.CatalogVariants.Add(variant);
        await db.SaveChangesAsync();

        var upd = await _client.PatchAsJsonAsync(
            $"/v1/businesses/{bizId}/catalog-items/{item.Id}/variants/{variant.Id}",
            new CatalogVariantUpdateRequest { Name = "New Var" });
        Assert.Equal(HttpStatusCode.OK, upd.StatusCode);
        var updated = await upd.Content.ReadFromJsonAsync<CatalogVariantOut>();
        Assert.NotNull(updated);
        Assert.Equal("New Var", updated.Name);

        var del = await _client.DeleteAsync(
            $"/v1/businesses/{bizId}/catalog-items/{item.Id}/variants/{variant.Id}");
        Assert.Equal(HttpStatusCode.NoContent, del.StatusCode);
    }

    // ==================== Batch Create ====================

    [Fact]
    public async Task CatalogItems_BatchCreate_Success()
    {
        await SetupAuth("batch@test.com");
        var bizId = await GetBusinessId();

        var scopeFactory = GetScopeFactory();
        using var scope = scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<PurchaseAssistantDbContext>();
        var cat = new ItemCategory { BusinessId = bizId, Name = "Cat" };
        db.ItemCategories.Add(cat);
        await db.SaveChangesAsync();
        var type = new CategoryType { CategoryId = cat.Id, Name = "Type" };
        db.CategoryTypes.Add(type);
        await db.SaveChangesAsync();

        var create = await _client.PostAsJsonAsync(
            $"/v1/businesses/{bizId}/catalog-items/batch",
            new CatalogBatchCreateRequest
            {
                Items = new List<CatalogBatchItem>
                {
                    new() { Name = "Item 1", TypeId = type.Id, DefaultUnit = "kg" },
                    new() { Name = "Item 2", TypeId = type.Id, DefaultUnit = "bag", DefaultKgPerBag = 50 },
                }
            });
        Assert.Equal(HttpStatusCode.Created, create.StatusCode);
        var result = await create.Content.ReadFromJsonAsync<CatalogBatchOut>();
        Assert.NotNull(result);
        Assert.Equal(2, result.Created);
        Assert.Equal(2, result.Items.Count);
    }

    // ==================== Fuzzy Check / Duplicates ====================

    [Fact]
    public async Task FuzzyCheck_ReturnsHits()
    {
        await SetupAuth("fuzzy@test.com");
        var bizId = await GetBusinessId();

        var scopeFactory = GetScopeFactory();
        using var scope = scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<PurchaseAssistantDbContext>();
        var cat = new ItemCategory { BusinessId = bizId, Name = "Cat" };
        db.ItemCategories.Add(cat);
        await db.SaveChangesAsync();

        db.CatalogItems.Add(new CatalogItem
        {
            BusinessId = bizId, CategoryId = cat.Id, Name = "Tomato",
            NormalizedName = "tomato", DefaultUnit = "kg",
        });
        db.CatalogItems.Add(new CatalogItem
        {
            BusinessId = bizId, CategoryId = cat.Id, Name = "Tomato Premium",
            NormalizedName = "tomato premium", DefaultUnit = "kg",
        });
        await db.SaveChangesAsync();

        var res = await _client.GetAsync(
            $"/v1/businesses/{bizId}/catalog/fuzzy-check?name=tomato");
        Assert.Equal(HttpStatusCode.OK, res.StatusCode);
        var fuzzy = await res.Content.ReadFromJsonAsync<CatalogFuzzyCheckResponse>();
        Assert.NotNull(fuzzy);
        Assert.NotEmpty(fuzzy.Hits);
    }

    [Fact]
    public async Task DuplicateClusters_ReturnsPairs()
    {
        await SetupAuth("dup@test.com");
        var bizId = await GetBusinessId();

        var scopeFactory = GetScopeFactory();
        using var scope = scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<PurchaseAssistantDbContext>();
        var cat = new ItemCategory { BusinessId = bizId, Name = "Cat" };
        db.ItemCategories.Add(cat);
        await db.SaveChangesAsync();

        db.CatalogItems.Add(new CatalogItem
        {
            BusinessId = bizId, CategoryId = cat.Id, Name = "Apple",
            NormalizedName = "apple", DefaultUnit = "kg",
        });
        db.CatalogItems.Add(new CatalogItem
        {
            BusinessId = bizId, CategoryId = cat.Id, Name = "aple",
            NormalizedName = "aple", DefaultUnit = "kg",
        });
        await db.SaveChangesAsync();

        var res = await _client.GetAsync(
            $"/v1/businesses/{bizId}/catalog/duplicate-clusters?minScore=0.7");
        Assert.Equal(HttpStatusCode.OK, res.StatusCode);
        var clusters = await res.Content.ReadFromJsonAsync<CatalogDuplicateClustersResponse>();
        Assert.NotNull(clusters);
    }

    // ==================== Bulk Operations ====================

    [Fact]
    public async Task BulkArchive_Success()
    {
        await SetupAuth("bulk-arch@test.com");
        var bizId = await GetBusinessId();

        var scopeFactory = GetScopeFactory();
        using var scope = scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<PurchaseAssistantDbContext>();
        var cat = new ItemCategory { BusinessId = bizId, Name = "Cat" };
        db.ItemCategories.Add(cat);
        await db.SaveChangesAsync();

        var item1 = new CatalogItem
        {
            BusinessId = bizId, CategoryId = cat.Id, Name = "Arch1",
            NormalizedName = "arch1", DefaultUnit = "kg",
        };
        var item2 = new CatalogItem
        {
            BusinessId = bizId, CategoryId = cat.Id, Name = "Arch2",
            NormalizedName = "arch2", DefaultUnit = "kg",
        };
        db.CatalogItems.AddRange(item1, item2);
        await db.SaveChangesAsync();

        var res = await _client.PostAsJsonAsync(
            $"/v1/businesses/{bizId}/catalog/items/bulk-archive",
            new BulkItemIdsIn { ItemIds = new List<Guid> { item1.Id, item2.Id } });
        Assert.Equal(HttpStatusCode.NoContent, res.StatusCode);
    }

    [Fact]
    public async Task BulkReorder_Success()
    {
        await SetupAuth("bulk-reorder@test.com");
        var bizId = await GetBusinessId();

        var scopeFactory = GetScopeFactory();
        using var scope = scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<PurchaseAssistantDbContext>();
        var cat = new ItemCategory { BusinessId = bizId, Name = "Cat" };
        db.ItemCategories.Add(cat);
        await db.SaveChangesAsync();

        var item1 = new CatalogItem
        {
            BusinessId = bizId, CategoryId = cat.Id, Name = "Reorder1",
            NormalizedName = "reorder1", DefaultUnit = "kg",
        };
        db.CatalogItems.Add(item1);
        await db.SaveChangesAsync();

        var res = await _client.PatchAsJsonAsync(
            $"/v1/businesses/{bizId}/catalog/items/bulk-reorder",
            new BulkReorderIn { ItemIds = new List<Guid> { item1.Id }, ReorderLevel = 100 });
        Assert.Equal(HttpStatusCode.OK, res.StatusCode);
    }

    // ==================== Supplier Purchase Defaults ====================

    [Fact]
    public async Task SupplierPurchaseDefaults_ReturnsList()
    {
        await SetupAuth("spd@test.com");
        var bizId = await GetBusinessId();

        var scopeFactory = GetScopeFactory();
        using var scope = scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<PurchaseAssistantDbContext>();
        var cat = new ItemCategory { BusinessId = bizId, Name = "Cat" };
        db.ItemCategories.Add(cat);
        await db.SaveChangesAsync();

        var item = new CatalogItem
        {
            BusinessId = bizId, CategoryId = cat.Id, Name = "SPD Item",
            DefaultUnit = "kg", NormalizedName = "spd item",
        };
        db.CatalogItems.Add(item);
        await db.SaveChangesAsync();

        var supplier = new Supplier { BusinessId = bizId, Name = "SPD Supplier" };
        db.Suppliers.Add(supplier);
        await db.SaveChangesAsync();

        db.SupplierItemDefaults.Add(new SupplierItemDefault
        {
            BusinessId = bizId, CatalogItemId = item.Id, SupplierId = supplier.Id,
            LastPrice = 100,
        });
        await db.SaveChangesAsync();

        var res = await _client.GetAsync(
            $"/v1/businesses/{bizId}/catalog-items/{item.Id}/supplier-purchase-defaults?supplierId={supplier.Id}");
        Assert.Equal(HttpStatusCode.OK, res.StatusCode);
        var spd = await res.Content.ReadFromJsonAsync<SupplierPurchaseDefaultsOut>();
        Assert.NotNull(spd);
        Assert.Equal(supplier.Id, spd.SupplierId);
    }

    // ==================== Insights and Lines ====================

    [Fact]
    public async Task Insights_ReturnsData()
    {
        await SetupAuth("insights@test.com");
        var bizId = await GetBusinessId();

        var scopeFactory = GetScopeFactory();
        using var scope = scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<PurchaseAssistantDbContext>();
        var cat = new ItemCategory { BusinessId = bizId, Name = "Cat" };
        db.ItemCategories.Add(cat);
        await db.SaveChangesAsync();

        var item = new CatalogItem
        {
            BusinessId = bizId, CategoryId = cat.Id, Name = "Insight Item",
            DefaultUnit = "kg", NormalizedName = "insight item",
        };
        db.CatalogItems.Add(item);
        await db.SaveChangesAsync();

        var res = await _client.GetAsync(
            $"/v1/businesses/{bizId}/catalog-items/{item.Id}/insights");
        Assert.Equal(HttpStatusCode.OK, res.StatusCode);
        var insights = await res.Content.ReadFromJsonAsync<CatalogItemInsightsOut>();
        Assert.NotNull(insights);
    }

    [Fact]
    public async Task CategoryInsights_ReturnsData()
    {
        await SetupAuth("cat-ins@test.com");
        var bizId = await GetBusinessId();

        var scopeFactory = GetScopeFactory();
        using var scope = scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<PurchaseAssistantDbContext>();
        var cat = new ItemCategory { BusinessId = bizId, Name = "CatForInsights" };
        db.ItemCategories.Add(cat);
        await db.SaveChangesAsync();

        db.CatalogItems.Add(new CatalogItem
        {
            BusinessId = bizId, CategoryId = cat.Id, Name = "CI Item",
            DefaultUnit = "kg", NormalizedName = "ci item",
        });
        await db.SaveChangesAsync();

        var res = await _client.GetAsync(
            $"/v1/businesses/{bizId}/item-categories/{cat.Id}/insights");
        Assert.Equal(HttpStatusCode.OK, res.StatusCode);
        var insights = await res.Content.ReadFromJsonAsync<CategoryInsightsOut>();
        Assert.NotNull(insights);
    }

    // ==================== Trade Summary ====================

    [Fact]
    public async Task CategoryTradeSummary_ReturnsData()
    {
        await SetupAuth("trade-sum@test.com");
        var bizId = await GetBusinessId();

        var scopeFactory = GetScopeFactory();
        using var scope = scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<PurchaseAssistantDbContext>();
        var cat = new ItemCategory { BusinessId = bizId, Name = "TradeCat" };
        db.ItemCategories.Add(cat);
        await db.SaveChangesAsync();

        db.CatalogItems.Add(new CatalogItem
        {
            BusinessId = bizId, CategoryId = cat.Id, Name = "Trade Item",
            DefaultUnit = "kg", NormalizedName = "trade item",
        });
        await db.SaveChangesAsync();

        var res = await _client.GetAsync(
            $"/v1/businesses/{bizId}/item-categories/{cat.Id}/trade-summary");
        Assert.Equal(HttpStatusCode.OK, res.StatusCode);
        var summary = await res.Content.ReadFromJsonAsync<CategoryTradeSummaryOut>();
        Assert.NotNull(summary);
    }

    // ==================== 404 / Validation Tests ====================

    [Fact]
    public async Task CatalogItems_NotFound_Returns404()
    {
        await SetupAuth("404@test.com");
        var bizId = await GetBusinessId();

        var res = await _client.GetAsync(
            $"/v1/businesses/{bizId}/catalog-items/{Guid.NewGuid()}");
        Assert.Equal(HttpStatusCode.NotFound, res.StatusCode);
    }

    [Fact]
    public async Task CreateItem_DuplicateName_Returns409()
    {
        await SetupAuth("dup-name@test.com");
        var bizId = await GetBusinessId();

        var scopeFactory = GetScopeFactory();
        using var scope = scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<PurchaseAssistantDbContext>();
        var cat = new ItemCategory { BusinessId = bizId, Name = "Cat" };
        db.ItemCategories.Add(cat);
        await db.SaveChangesAsync();
        var type = new CategoryType { CategoryId = cat.Id, Name = "Type" };
        db.CategoryTypes.Add(type);
        await db.SaveChangesAsync();

        db.CatalogItems.Add(new CatalogItem
        {
            BusinessId = bizId, CategoryId = cat.Id, TypeId = type.Id,
            Name = "Unique Name", NormalizedName = "unique name", DefaultUnit = "kg",
        });
        await db.SaveChangesAsync();

        var create = await _client.PostAsJsonAsync(
            $"/v1/businesses/{bizId}/catalog-items",
            new CatalogItemCreateRequest
            {
                CategoryId = cat.Id,
                TypeId = type.Id,
                Name = "Unique Name",
                DefaultUnit = "kg",
            });
        Assert.Equal(HttpStatusCode.Conflict, create.StatusCode);
    }

    [Fact]
    public async Task Unauthorized_Returns401()
    {
        _client.DefaultRequestHeaders.Authorization = null;
        var res = await _client.GetAsync($"/v1/businesses/{Guid.NewGuid()}/catalog-items");
        Assert.Equal(HttpStatusCode.Unauthorized, res.StatusCode);
    }
}
