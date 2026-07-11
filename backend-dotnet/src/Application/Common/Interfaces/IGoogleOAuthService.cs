namespace PurchaseAssistant.Application.Common.Interfaces;

public record GoogleClaims(string Sub, string Email, string? Name, bool EmailVerified);

public interface IGoogleOAuthService
{
    Task<GoogleClaims> VerifyIdToken(string idToken, List<string> audiences);
}
