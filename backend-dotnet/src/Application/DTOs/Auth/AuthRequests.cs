namespace PurchaseAssistant.Application.DTOs.Auth;

public record RegisterRequest(
    string Email,
    string Username,
    string Password,
    string? Name = null);

public record LoginRequest(
    string? Email = null,
    string? Identifier = null,
    string? Password = null,
    string? DeviceToken = null);

public record GoogleAuthRequest(string IdToken);

public record RefreshRequest(string RefreshToken);

public record ForgotPasswordRequest(string Email);

public record ResetPasswordRequest(string Token, string NewPassword);

public record TokenPair(string AccessToken, string RefreshToken, int ExpiresIn);
