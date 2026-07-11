namespace PurchaseAssistant.Application.Common.Interfaces;

public interface IUsernameService
{
    Task<string> AllocateUsername(string? requested, string phoneDigits, string fullName);
}
