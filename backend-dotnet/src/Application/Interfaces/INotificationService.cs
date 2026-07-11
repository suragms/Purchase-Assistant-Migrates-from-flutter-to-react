using PurchaseAssistant.Domain.Entities.Notifications;

namespace PurchaseAssistant.Application.Interfaces;

public interface INotificationService
{
    Task<int> EmitNotificationAsync(
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
        CancellationToken ct = default);

    Task ListAsync();
    Task GetSummaryAsync();
    Task GetUnreadCountAsync();
    Task MarkReadAsync();
    Task MarkAllReadAsync();
    Task ClearAllAsync();
    Task CreateClientEventAsync();
}
