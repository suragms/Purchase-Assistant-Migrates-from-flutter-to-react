using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using PurchaseAssistant.Application.Interfaces;
using PurchaseAssistant.Infrastructure.Data;

namespace PurchaseAssistant.Infrastructure.BackgroundServices;

public class EveningPhysicalCountReminderService : Microsoft.Extensions.Hosting.BackgroundService
{
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly ILogger<EveningPhysicalCountReminderService> _logger;

    private static readonly TimeSpan TargetTimeUtc = TimeSpan.FromHours(12); // 18:00 IST = 12:30 UTC → round to 12:00 UTC

    public EveningPhysicalCountReminderService(
        IServiceScopeFactory scopeFactory,
        ILogger<EveningPhysicalCountReminderService> logger)
    {
        _scopeFactory = scopeFactory;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("EveningPhysicalCountReminderService started");

        while (!stoppingToken.IsCancellationRequested)
        {
            var now = DateTime.UtcNow;
            var nextRun = now.Date.Add(TargetTimeUtc);
            if (now > nextRun) nextRun = nextRun.AddDays(1);

            var delay = nextRun - now;
            _logger.LogDebug("Next reminder run at {Time:O} (in {Delay})", nextRun, delay);

            await Task.Delay(delay, stoppingToken);

            try
            {
                await SendRemindersAsync(stoppingToken);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                _logger.LogError(ex, "Error sending evening reminders");
            }
        }
    }

    private async Task SendRemindersAsync(CancellationToken ct)
    {
        using var scope = _scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<PurchaseAssistantDbContext>();
        var notif = scope.ServiceProvider.GetRequiredService<INotificationService>();

        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        var businessIds = await db.Businesses.Select(b => b.Id).ToListAsync(ct);

        var inserted = 0;
        foreach (var bizId in businessIds)
        {
            var n = await notif.EmitNotificationAsync(
                bizId,
                kind: "physical_count_reminder",
                title: "Evening stock check",
                body: "Review physical counts on the warehouse floor before closing",
                priority: "medium",
                category: "warehouse",
                dedupeKey: $"evening_physical:{bizId}:{today:yyyy-MM-dd}",
                actionRoute: "/stock",
                ownerOnly: true,
                ct: ct);
            inserted += n;
        }

        if (inserted > 0)
            _logger.LogInformation("Sent {Count} evening physical count reminders", inserted);
    }
}
