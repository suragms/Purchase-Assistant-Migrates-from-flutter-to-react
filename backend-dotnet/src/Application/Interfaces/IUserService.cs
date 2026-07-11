namespace PurchaseAssistant.Application.Interfaces;

public interface IUserService
{
    Task CreateUserAsync();
    Task ListUsersAsync();
    Task GetActiveSessionsAsync();
    Task BulkActionAsync();
    Task GetUserAsync();
    Task UpdateUserAsync();
    Task DeleteUserAsync();
    Task ResetPasswordAsync();
    Task GetCredentialsAsync();
    Task GetCreatedItemsAsync();
    Task GetStockAdjustmentsAsync();
    Task GetPurchasesAsync();
    Task GetLedgerAsync();
    Task GetPermissionsAsync();
    Task UpdatePermissionsAsync();
}
