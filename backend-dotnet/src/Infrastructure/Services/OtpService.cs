using System.Collections.Concurrent;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using PurchaseAssistant.Application.Common.Interfaces;

namespace PurchaseAssistant.Infrastructure.Services;

public class OtpService : IOtpService
{
    private readonly ILogger<OtpService> _logger;
    private readonly bool _devReturnOtp;
    private readonly string _devOtpCode;
    private readonly int _otpRequestsPer10Min;
    private readonly int _otpFailedLockoutThreshold;
    private readonly int _otpFailedLockoutMinutes;

    private static readonly ConcurrentDictionary<string, OtpEntry> Store = new();
    private static readonly ConcurrentDictionary<string, OtpAttemptState> AttemptStates = new();
    private static readonly ConcurrentDictionary<string, SlidingWindowCounter> RequestCounters = new();

    private record OtpEntry(string Code, DateTime ExpiresAt);
    private record OtpAttemptState(int FailedAttempts, DateTime LockedUntil);
    private record SlidingWindowCounter(int Count, DateTime WindowStart);

    public bool IsDevOtpMode => _devReturnOtp;
    public string DevOtpCode => _devOtpCode;

    public OtpService(IConfiguration configuration, ILogger<OtpService> logger)
    {
        _logger = logger;
        _devReturnOtp = configuration.GetValue<bool>("AppSettings:DevReturnOtp", true);
        _devOtpCode = configuration.GetValue<string>("AppSettings:DevOtpCode") ?? "000000";
        _otpRequestsPer10Min = configuration.GetValue<int>("AppSettings:OtpRequestsPer10Minutes", 3);
        _otpFailedLockoutThreshold = configuration.GetValue<int>("AppSettings:OtpFailedLockoutThreshold", 5);
        _otpFailedLockoutMinutes = configuration.GetValue<int>("AppSettings:OtpFailedLockoutMinutes", 30);
    }

    public async Task<string> GenerateAndStoreOtp(string phone, string? requesterIp = null)
    {
        string code;
        if (_devReturnOtp)
        {
            code = _devOtpCode;
        }
        else
        {
            code = Random.Shared.Next(0, 999999).ToString("D6");
        }

        Store[phone] = new OtpEntry(code, DateTime.UtcNow.AddMinutes(10));
        _logger.LogInformation("OTP issued | phone={Phone} ip={Ip}", phone, requesterIp ?? "-");

        return await Task.FromResult(code);
    }

    public Task<string?> GetStoredOtp(string phone)
    {
        if (Store.TryGetValue(phone, out var entry))
        {
            if (DateTime.UtcNow < entry.ExpiresAt)
                return Task.FromResult<string?>(entry.Code);
            Store.TryRemove(phone, out _);
        }
        return Task.FromResult<string?>(null);
    }

    public Task DeleteOtp(string phone)
    {
        Store.TryRemove(phone, out _);
        return Task.CompletedTask;
    }

    public bool RequestAllowed(string phone)
    {
        var key = $"otp:phone:{phone}";
        var now = DateTime.UtcNow;
        var counter = RequestCounters.AddOrUpdate(key,
            _ => new SlidingWindowCounter(1, now),
            (_, existing) =>
            {
                if (now - existing.WindowStart > TimeSpan.FromMinutes(10))
                    return new SlidingWindowCounter(1, now);
                return existing with { Count = existing.Count + 1 };
            });
        return counter.Count <= _otpRequestsPer10Min;
    }

    public bool VerifyAllowed(string phone)
    {
        if (AttemptStates.TryGetValue(phone, out var state))
        {
            return DateTime.UtcNow >= state.LockedUntil;
        }
        return true;
    }

    public void RecordVerifyFailure(string phone)
    {
        var state = AttemptStates.AddOrUpdate(phone,
            _ => new OtpAttemptState(1, DateTime.MinValue),
            (_, existing) =>
            {
                var attempts = existing.FailedAttempts + 1;
                if (attempts >= _otpFailedLockoutThreshold)
                {
                    var lockedUntil = DateTime.UtcNow.AddMinutes(_otpFailedLockoutMinutes);
                    _logger.LogWarning("OTP verify lockout applied | phone={Phone} minutes={Minutes}",
                        phone, _otpFailedLockoutMinutes);
                    return new OtpAttemptState(attempts, lockedUntil);
                }
                _logger.LogInformation("OTP verify failed | phone={Phone} attempts={Attempts}",
                    phone, attempts);
                return existing with { FailedAttempts = attempts };
            });
    }

    public void RecordVerifySuccess(string phone)
    {
        AttemptStates.TryRemove(phone, out _);
    }
}
