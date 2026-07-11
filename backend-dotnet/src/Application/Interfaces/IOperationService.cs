namespace PurchaseAssistant.Application.Interfaces;

public interface IOperationService
{
    Task GetDailyUsageAsync();
    Task CreateDailyUsageAsync();
    Task ListChecklistsAsync();
    Task CreateChecklistCompletionAsync();
    Task ListChecklistCompletionsAsync();
}
