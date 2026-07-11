using Microsoft.EntityFrameworkCore;
using PurchaseAssistant.Application.Interfaces;
using PurchaseAssistant.Domain.Entities.Notifications;
using PurchaseAssistant.Infrastructure.Data;

namespace PurchaseAssistant.Infrastructure.Services;

public class NotificationService : INotificationService
{
    private readonly PurchaseAssistantDbContext _db;

    private static readonly HashSet<string> OwnerRoles = ["owner", "admin", "manager"];

    public NotificationService(PurchaseAssistantDbContext db)
    {
        _db = db;
    }

    public async Task<int> EmitNotificationAsync(
        Guid businessId,
        string kind,
        string title,
        string? body = null,
        string priority = "medium",
        string category = "system",
        string? dedupeKey = null,
        string? actionRoute = null,
        Guid? relatedPurchaseId = null,
        Guid? relatedItemId = null,
        Guid? relatedSupplierId = null,
        bool ownerOnly = false,
        List<string>? targetRoles = null,
        CancellationToken ct = default)
    {
        if (!string.IsNullOrEmpty(dedupeKey))
        {
            var exists = await _db.Notifications.AnyAsync(n =>
                n.BusinessId == businessId && n.DedupeKey == dedupeKey, ct);
            if (exists) return 0;
        }

        var userIds = await ResolveRecipientIdsAsync(businessId, ownerOnly, targetRoles, ct);
        if (userIds.Count == 0) return 0;

        foreach (var uid in userIds)
        {
            _db.Notifications.Add(new Notification
            {
                BusinessId = businessId,
                UserId = uid,
                Kind = kind,
                Title = title,
                Body = body,
                Priority = priority,
                Category = category,
                DedupeKey = dedupeKey,
                ActionRoute = actionRoute,
                RelatedPurchaseId = relatedPurchaseId,
                RelatedItemId = relatedItemId,
            });
        }

        await _db.SaveChangesAsync(ct);
        return userIds.Count;
    }

    private async Task<List<Guid>> ResolveRecipientIdsAsync(
        Guid businessId, bool ownerOnly, List<string>? targetRoles, CancellationToken ct)
    {
        var q = _db.Memberships.Where(m => m.BusinessId == businessId);

        if (targetRoles is { Count: > 0 })
        {
            var allowed = targetRoles.Select(r => r.Trim().ToLower()).ToHashSet();
            q = q.Where(m => allowed.Contains(m.Role.ToLower()));
        }
        else if (ownerOnly)
        {
            q = q.Where(m => OwnerRoles.Contains(m.Role.ToLower()));
        }

        return await q.Select(m => m.UserId).ToListAsync(ct);
    }

    public Task ListAsync() => throw new NotImplementedException();
    public Task GetSummaryAsync() => throw new NotImplementedException();
    public Task GetUnreadCountAsync() => throw new NotImplementedException();
    public Task MarkReadAsync() => throw new NotImplementedException();
    public Task MarkAllReadAsync() => throw new NotImplementedException();
    public Task ClearAllAsync() => throw new NotImplementedException();
    public Task CreateClientEventAsync() => throw new NotImplementedException();
}
