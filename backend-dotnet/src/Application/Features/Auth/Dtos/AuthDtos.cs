using System.ComponentModel.DataAnnotations;

namespace PurchaseAssistant.Application.Features.Auth.Dtos;

public class RegisterRequest
{
    [Required, StringLength(320, MinimumLength = 5)]
    public string Email { get; set; } = string.Empty;

    [Required, StringLength(64, MinimumLength = 3)]
    [RegularExpression(@"^[a-z0-9_]{3,64}$")]
    public string Username { get; set; } = string.Empty;

    [Required, StringLength(128, MinimumLength = 8)]
    public string Password { get; set; } = string.Empty;

    [StringLength(255)]
    public string? Name { get; set; }
}

public class LoginRequest
{
    [StringLength(320, MinimumLength = 5)]
    public string? Email { get; set; }

    [StringLength(320)]
    public string? Identifier { get; set; }

    [Required, StringLength(128, MinimumLength = 1)]
    public string Password { get; set; } = string.Empty;

    [StringLength(512)]
    public string? DeviceToken { get; set; }
}

public class TokenPairResponse
{
    public string AccessToken { get; set; } = string.Empty;
    public string RefreshToken { get; set; } = string.Empty;
    public int ExpiresIn { get; set; }
}

public class GoogleAuthRequest
{
    [Required, StringLength(12000, MinimumLength = 20)]
    public string IdToken { get; set; } = string.Empty;
}

public class RefreshRequest
{
    [Required]
    public string RefreshToken { get; set; } = string.Empty;
}

public class ForgotPasswordRequest
{
    [Required, StringLength(320, MinimumLength = 3)]
    public string Email { get; set; } = string.Empty;
}

public class ResetPasswordRequest
{
    [Required, StringLength(2000, MinimumLength = 10)]
    public string Token { get; set; } = string.Empty;

    [Required, StringLength(128, MinimumLength = 8)]
    public string NewPassword { get; set; } = string.Empty;
}

public class ForgotPasswordResponse
{
    public bool Ok { get; set; } = true;
    public string Message { get; set; } = string.Empty;
    public string? DevResetToken { get; set; }
}

public class ResetPasswordResponse
{
    public bool Ok { get; set; } = true;
    public string Message { get; set; } = string.Empty;
}
