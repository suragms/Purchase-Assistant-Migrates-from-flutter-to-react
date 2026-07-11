namespace PurchaseAssistant.Application.Common.Interfaces;

public interface IOtpService
{
    Task<string> GenerateAndStoreOtp(string phone, string? requesterIp = null);
    Task<string?> GetStoredOtp(string phone);
    Task DeleteOtp(string phone);
    bool RequestAllowed(string phone);
    bool VerifyAllowed(string phone);
    void RecordVerifyFailure(string phone);
    void RecordVerifySuccess(string phone);
    bool IsDevOtpMode { get; }
    string DevOtpCode { get; }
}
