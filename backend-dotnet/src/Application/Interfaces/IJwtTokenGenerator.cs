namespace PurchaseAssistant.Application.Interfaces;

public record AccessTokenClaims(Guid UserId, int TokenVersion);

public interface IJwtTokenGenerator
{
    string GenerateAccessToken(Guid userId, int tokenVersion);
    string GenerateRefreshToken(Guid userId);
    AccessTokenClaims? DecodeAccessToken(string token);
    Guid? DecodeRefreshToken(string token);
}
