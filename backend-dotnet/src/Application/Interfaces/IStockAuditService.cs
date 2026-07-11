namespace PurchaseAssistant.Application.Interfaces;

public interface IStockAuditService
{
    Task ListAsync();
    Task CreateAsync();
    Task GetAsync();
    Task UpdateAsync();
    Task AddItemAsync();
    Task CompleteAsync();
    Task ResolveDiscrepanciesAsync();
}
