namespace PurchaseAssistant.Application.DTOs.Notifications;

public record NotificationOut(
    Guid Id, string? Kind, string? Title, string? Body,
    string? Priority, string? Category, DateTime? ReadAt, DateTime CreatedAt);

public record NotificationSummaryOut(Dictionary<string, int> UnreadCounts);
public record UnreadCountOut(int Count);
public record NotificationReadPatch(bool Read);
public record NotificationBulkActionOut(int Affected);

public record ClientNotificationEventIn(string Kind, string? Title = null, string? Body = null);
