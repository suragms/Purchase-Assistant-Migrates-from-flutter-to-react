using System.Security.Cryptography;
using System.Text.RegularExpressions;
using PurchaseAssistant.Application.Common.Interfaces;

namespace PurchaseAssistant.Infrastructure.Services;

public class PasswordService : IPasswordService
{
    private static readonly HashSet<string> CommonPasswords = new(StringComparer.OrdinalIgnoreCase)
    {
        "password", "password123", "qwerty123", "admin123",
        "12345678", "letmein", "welcome123",
    };

    private const string Alphabet = "23456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz";

    public void ValidateStrength(string plain)
    {
        var pwd = (plain ?? "").Trim();
        if (pwd.Length < 8)
            throw new ArgumentException("Password must be at least 8 characters");
        if (!Regex.IsMatch(pwd, @"\d"))
            throw new ArgumentException("Password must include at least one number");
        if (CommonPasswords.Contains(pwd.ToLowerInvariant()))
            throw new ArgumentException("Choose a stronger password");
    }

    public string Hash(string plain)
    {
        ValidateStrength(plain);
        return BCrypt.Net.BCrypt.HashPassword(plain, workFactor: 12);
    }

    public bool Verify(string plain, string passwordHash)
    {
        try
        {
            return BCrypt.Net.BCrypt.Verify(plain, passwordHash);
        }
        catch
        {
            return false;
        }
    }

    public string GenerateReadablePassword(string? fullName = null, int length = 8)
    {
        if (!string.IsNullOrWhiteSpace(fullName))
        {
            var token = Regex.Replace(fullName.Trim().ToLowerInvariant().Split(' ')[0], @"[^a-z0-9]", "");
            if (token.Length >= 2)
            {
                var suffix = RandomNumberGenerator.GetInt32(0, 999).ToString("D3");
                return $"{token[..Math.Min(token.Length, 12)]}@{suffix}";
            }
        }
        var chars = new char[length];
        for (int i = 0; i < length; i++)
            chars[i] = Alphabet[RandomNumberGenerator.GetInt32(Alphabet.Length)];
        return new string(chars);
    }
}
