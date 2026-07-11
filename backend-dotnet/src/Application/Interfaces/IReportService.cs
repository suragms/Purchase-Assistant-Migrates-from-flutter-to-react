namespace PurchaseAssistant.Application.Interfaces;

public interface IReportService
{
    Task GetTradeReportAsync();
    Task ListSavedViewsAsync();
    Task CreateSavedViewAsync();
    Task UpdateSavedViewAsync();
    Task DeleteSavedViewAsync();
}
