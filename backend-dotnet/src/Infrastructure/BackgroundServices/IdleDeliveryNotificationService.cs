using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using PurchaseAssistant.Application.Interfaces;
using PurchaseAssistant.Infrastructure.Data;

namespace PurchaseAssistant.Infrastructure.BackgroundServices;

public class IdleDeliveryNotificationService : Microsoft.Extensions.Hosting.BackgroundService
{
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly ILogger<IdleDeliveryNotificationService> _logger;
    private static readonly HashSet<string> IdleStatuses = ["dispatched", "in_transit"];

    public IdleDeliveryNotificationService(
        IServiceScopeFactory scopeFactory,
        ILogger<IdleDeliveryNotificationService> logger)
    {
        _scopeFactory = scopeFactory;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("IdleDeliveryNotificationService started");

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await ScanIdleDeliveriesAsync(stoppingToken);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                _logger.LogError(ex, "Error scanning idle deliveries");
            }

            await Task.Delay(TimeSpan.FromMinutes(5), stoppingToken);
        }
    }

    private async Task ScanIdleDeliveriesAsync(CancellationToken ct)
    {
        using var scope = _scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<PurchaseAssistantDbContext>();
        var notif = scope.ServiceProvider.GetRequiredService<INotificationService>();

        var cutoff = DateTime.UtcNow.AddHours(-2);
        var today = DateOnly.FromDateTime(DateTime.UtcNow);

        var purchases = await db.TradePurchases
            .Where(tp =>
                tp.DeliveryStatus != null &&
                IdleStatuses.Contains(tp.DeliveryStatus) &&
                tp.CreatedAt <= cutoff)
            .ToListAsync(ct);

        if (purchases.Count == 0) return;

        var inserted = 0;
        foreach (var tp in purchases)
        {
            var hid = tp.HumanId ?? tp.Id.ToString()[..8];
            var n = await notif.EmitNotificationAsync(
                tp.BusinessId,
                kind: "delivery_idle",
                title: $"Delivery idle · {hid}",
                body: "Dispatched 2+ hours ago — follow up or mark arrived",
                priority: "high",
                category: "purchase",
                dedupeKey: $"delivery_idle:{tp.Id}:{DateOnly.FromDateTime(DateTime.UtcNow):yyyy-MM-dd}",
                actionRoute: $"/purchase/detail/{tp.Id}",
                relatedPurchaseId: tp.Id,
                ownerOnly: true,
                ct: ct);
            inserted += n;
        }

        if (inserted > 0)
            _logger.LogInformation("Inserted {Count} idle delivery notifications", inserted);
    }
}
