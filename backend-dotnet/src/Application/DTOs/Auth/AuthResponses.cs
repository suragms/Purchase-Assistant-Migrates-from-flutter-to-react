namespace PurchaseAssistant.Application.DTOs.Auth;

public record ForgotPasswordResponse(bool Ok, string? Message = null, string? DevResetToken = null);

public record ResetPasswordResponse(bool Ok, string? Message = null);
