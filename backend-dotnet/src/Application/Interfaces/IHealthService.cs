namespace PurchaseAssistant.Application.Interfaces;

public interface IHealthService
{
    Task GetRootAsync();
    Task GetHeadRootAsync();
    Task GetLiveAsync();
    Task GetHealthAsync();
    Task GetReadyAsync();
    Task GetDbCheckAsync();
}
