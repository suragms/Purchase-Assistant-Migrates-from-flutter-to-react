namespace PurchaseAssistant.Application.Common.Interfaces;

public interface IPasswordService
{
    void ValidateStrength(string plain);
    string Hash(string plain);
    bool Verify(string plain, string passwordHash);
    string GenerateReadablePassword(string? fullName = null, int length = 8);
}
