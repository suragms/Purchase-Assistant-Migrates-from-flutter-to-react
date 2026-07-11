namespace PurchaseAssistant.Application.Interfaces;

public interface ICatalogService
{
    // Categories
    Task ListCategoriesAsync();
    Task CreateCategoryAsync();
    Task GetCategoryAsync();
    Task UpdateCategoryAsync();
    Task DeleteCategoryAsync();
    Task GetCategoryTradeSummaryAsync();
    Task GetCategoryInsightsAsync();

    // Category Types
    Task ListCategoryTypesAsync();
    Task CreateCategoryTypeAsync();
    Task UpdateCategoryTypeAsync();
    Task DeleteCategoryTypeAsync();
    Task GetCategoryTypesIndexAsync();

    // Catalog Items
    Task ListCatalogItemsAsync();
    Task CreateCatalogItemAsync();
    Task CreateFromScanAsync();
    Task BatchCreateAsync();
    Task GetCatalogItemAsync();
    Task UpdateItemCodeAsync();
    Task UpdateBarcodeAsync();
    Task GenerateCodeAsync();
    Task GetSupplierDefaultsAsync();
    Task GetTradeSupplierPricesAsync();
    Task GetItemInsightsAsync();
    Task GetItemLinesAsync();
    Task FuzzyCheckAsync();
    Task DuplicateClustersAsync();
    Task BulkArchiveAsync();
    Task BulkReorderAsync();

    // Variants
    Task ListVariantsAsync();
    Task CreateVariantAsync();
    Task UpdateVariantAsync();
    Task DeleteVariantAsync();
}
