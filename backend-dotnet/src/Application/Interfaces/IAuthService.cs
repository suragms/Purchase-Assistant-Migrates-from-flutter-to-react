namespace PurchaseAssistant.Application.Interfaces;

public interface IAuthService
{
    Task RegisterAsync();
    Task LoginAsync();
    Task GoogleAuthAsync();
    Task RefreshTokenAsync();
    Task ForgotPasswordAsync();
    Task ResetPasswordAsync();
}
