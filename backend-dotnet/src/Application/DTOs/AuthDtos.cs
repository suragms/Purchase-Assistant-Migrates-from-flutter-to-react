using System.Text.Json.Serialization;

namespace PurchaseAssistant.Application.DTOs;

public record RegisterRequest(
    string Email,
    string Username,
    string Password,
    string? Name
);

public record LoginRequest(
    string? Email,
    string? Password,
    string? DeviceToken
);

public record TokenPair(
    [property: JsonPropertyName("access_token")] string AccessToken,
    [property: JsonPropertyName("refresh_token")] string RefreshToken,
    [property: JsonPropertyName("expires_in")] int ExpiresIn
);

public record GoogleAuthRequest(
    [property: JsonPropertyName("id_token")] string IdToken
);

public record RefreshRequest(
    [property: JsonPropertyName("refresh_token")] string RefreshToken
);

public record ForgotPasswordRequest(string Email);

public record ResetPasswordRequest(string Token, string NewPassword);

public record ForgotPasswordResponse(bool Ok, string Message, string? DevResetToken = null);

public record ResetPasswordResponse(bool Ok, string Message);
