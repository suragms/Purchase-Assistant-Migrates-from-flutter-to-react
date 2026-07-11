namespace PurchaseAssistant.Application.Interfaces;

public interface IActivityLogService
{
    Task CreateAsync();
    Task ListAsync();
}
