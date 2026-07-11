using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Microsoft.Extensions.Configuration;
using Microsoft.IdentityModel.Tokens;
using PurchaseAssistant.Application.Common.Interfaces;

namespace PurchaseAssistant.Infrastructure.Services;

public class JwtService : IJwtService
{
    private readonly string _secret;
    private readonly string _refreshSecret;
    private readonly int _accessTtlMinutes;
    private readonly int _refreshTtlDays;

    public JwtService(IConfiguration configuration)
    {
        _secret = configuration["Jwt:Secret"] ?? "change-me-min-32-chars-dev-only";
        _refreshSecret = configuration["Jwt:RefreshSecret"] ?? "change-me-min-32-chars-refresh-dev";
        _accessTtlMinutes = int.TryParse(configuration["Jwt:AccessTtlMinutes"], out var a) ? a : 15;
        _refreshTtlDays = int.TryParse(configuration["Jwt:RefreshTtlDays"], out var r) ? r : 30;
    }

    public string CreateAccessToken(Guid userId, int tokenVersion = 0)
    {
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_secret));
        var creds = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);
        var claims = new[]
        {
            new Claim(JwtRegisteredClaimNames.Sub, userId.ToString()),
            new Claim("typ", "access"),
            new Claim("tv", tokenVersion.ToString()),
        };
        var token = new JwtSecurityToken(
            claims: claims,
            expires: DateTime.UtcNow.AddMinutes(_accessTtlMinutes),
            signingCredentials: creds
        );
        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    public string CreateRefreshToken(Guid userId)
    {
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_refreshSecret));
        var creds = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);
        var claims = new[]
        {
            new Claim(JwtRegisteredClaimNames.Sub, userId.ToString()),
            new Claim("typ", "refresh"),
        };
        var token = new JwtSecurityToken(
            claims: claims,
            expires: DateTime.UtcNow.AddDays(_refreshTtlDays),
            signingCredentials: creds
        );
        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    public AccessTokenClaims? DecodeAccessToken(string token)
    {
        try
        {
            var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_secret));
            var handler = new JwtSecurityTokenHandler();
            var result = handler.ValidateToken(token, new TokenValidationParameters
            {
                ValidateIssuer = false,
                ValidateAudience = false,
                ValidateLifetime = true,
                ValidateIssuerSigningKey = true,
                IssuerSigningKey = key,
                ClockSkew = TimeSpan.Zero,
            }, out var validatedToken);

            var jwt = (JwtSecurityToken)validatedToken;
            if (jwt.Claims.FirstOrDefault(c => c.Type == "typ")?.Value != "access")
                return null;

            var userId = jwt.Claims.FirstOrDefault(c => c.Type == JwtRegisteredClaimNames.Sub)?.Value;
            if (userId == null) return null;

            var tv = jwt.Claims.FirstOrDefault(c => c.Type == "tv")?.Value;
            return new AccessTokenClaims(
                Guid.Parse(userId),
                int.TryParse(tv, out var t) ? t : 0
            );
        }
        catch
        {
            return null;
        }
    }

    public Guid? DecodeRefreshToken(string token)
    {
        try
        {
            var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(_refreshSecret));
            var handler = new JwtSecurityTokenHandler();
            var result = handler.ValidateToken(token, new TokenValidationParameters
            {
                ValidateIssuer = false,
                ValidateAudience = false,
                ValidateLifetime = true,
                ValidateIssuerSigningKey = true,
                IssuerSigningKey = key,
                ClockSkew = TimeSpan.Zero,
            }, out var validatedToken);

            var jwt = (JwtSecurityToken)validatedToken;
            if (jwt.Claims.FirstOrDefault(c => c.Type == "typ")?.Value != "refresh")
                return null;

            var userId = jwt.Claims.FirstOrDefault(c => c.Type == JwtRegisteredClaimNames.Sub)?.Value;
            return userId != null ? Guid.Parse(userId) : null;
        }
        catch
        {
            return null;
        }
    }
}
