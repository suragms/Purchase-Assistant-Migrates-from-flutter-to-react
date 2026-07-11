using System.Text.RegularExpressions;
using Microsoft.EntityFrameworkCore;
using PurchaseAssistant.Application.Common.Interfaces;
using PurchaseAssistant.Domain.Entities.Core;
using PurchaseAssistant.Infrastructure.Data;

namespace PurchaseAssistant.Infrastructure.Services;

public class UsernameService : IUsernameService
{
    private readonly PurchaseAssistantDbContext _db;

    public UsernameService(PurchaseAssistantDbContext db)
    {
        _db = db;
    }

    public async Task<string> AllocateUsername(string? requested, string phoneDigits, string fullName)
    {
        if (!string.IsNullOrWhiteSpace(requested))
        {
            var candidate = requested.Trim().ToLowerInvariant().Replace(" ", "_")[..Math.Min(64, requested.Length)];
            if (Regex.IsMatch(candidate, @"^[a-z0-9_]{3,64}$"))
            {
                var exists = await _db.Users.AnyAsync(u => u.Username == candidate);
                if (!exists)
                    return candidate;
                throw new ArgumentException("username_taken");
            }
        }

        var base2 = phoneDigits.Length >= 4
            ? $"staff_{phoneDigits[^4..]}"
            : "staff";

        var slug = SlugFromName(fullName);
        if (!string.IsNullOrEmpty(slug) && slug != "staff")
            base2 = slug[..Math.Min(slug.Length, 48)];

        for (int attempt = 0; attempt < 12; attempt++)
        {
            var suffix = attempt == 0 ? "" : $"_{Guid.NewGuid().ToString("N")[..4]}";
            var candidate2 = $"{base2}{suffix}"[..Math.Min(64, $"{base2}{suffix}".Length)];
            var exists2 = await _db.Users.AnyAsync(u => u.Username == candidate2);
            if (!exists2)
                return candidate2;
        }
        return $"staff_{Guid.NewGuid():N}"[..Math.Min(64, $"staff_{Guid.NewGuid():N}".Length)];
    }

    private static string SlugFromName(string name)
    {
        var s = (name ?? "").Trim().ToLowerInvariant();
        s = Regex.Replace(s, @"[^a-z0-9]+", "_");
        s = Regex.Replace(s, @"_+", "_").Trim('_');
        return (s.Length > 0 ? s[..Math.Min(s.Length, 48)] : "staff");
    }
}
