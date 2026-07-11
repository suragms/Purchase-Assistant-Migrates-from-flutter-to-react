namespace PurchaseAssistant.Application.Interfaces;

public interface IEmailService
{
    Task SendPasswordResetAsync(string email, string token);
    Task SendNotificationAsync(string email, string subject, string body);
}
