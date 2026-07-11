namespace PurchaseAssistant.Application.Common.Interfaces;

public record TokenPairDto(string AccessToken, string RefreshToken, int ExpiresIn);

public interface IAuthService
{
    string NormalizeLoginEmail(string email);
    Task<TokenPairDto> Register(string email, string username, string password, string? name);
    Task<TokenPairDto> Login(string email, string password, string? deviceToken);
    Task<TokenPairDto> LoginWithGoogle(string idToken);
    Task<TokenPairDto> RefreshToken(string refreshToken);
    Task ForgotPassword(string email);
    Task ResetPassword(string token, string newPassword);
}
