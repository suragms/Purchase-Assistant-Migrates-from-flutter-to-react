using Google.Apis.Auth;
using PurchaseAssistant.Application.Common.Interfaces;

namespace PurchaseAssistant.Infrastructure.Services;

public class GoogleOAuthService : IGoogleOAuthService
{
    public async Task<GoogleClaims> VerifyIdToken(string idToken, List<string> audiences)
    {
        if (audiences == null || audiences.Count == 0)
            throw new InvalidOperationException("No GOOGLE_OAUTH_CLIENT_IDS configured");

        GoogleJsonWebSignature.Payload? payload = null;
        Exception? last = null;

        foreach (var aud in audiences)
        {
            try
            {
                var settings = new GoogleJsonWebSignature.ValidationSettings
                {
                    Audience = new[] { aud }
                };
                payload = await GoogleJsonWebSignature.ValidateAsync(idToken, settings);
                break;
            }
            catch (Exception ex)
            {
                last = ex;
            }
        }

        if (payload == null)
            throw new InvalidOperationException(
                "Google ID token could not be verified for configured client IDs",
                last);

        return new GoogleClaims(
            Sub: payload.Subject,
            Email: payload.Email,
            Name: payload.Name,
            EmailVerified: payload.EmailVerified
        );
    }
}
