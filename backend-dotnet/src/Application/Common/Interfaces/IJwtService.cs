namespace PurchaseAssistant.Application.Common.Interfaces;

public record AccessTokenClaims(Guid UserId, int TokenVersion);

public interface IJwtService
{
    string CreateAccessToken(Guid userId, int tokenVersion = 0);
    string CreateRefreshToken(Guid userId);
    AccessTokenClaims? DecodeAccessToken(string token);
    Guid? DecodeRefreshToken(string token);
}
