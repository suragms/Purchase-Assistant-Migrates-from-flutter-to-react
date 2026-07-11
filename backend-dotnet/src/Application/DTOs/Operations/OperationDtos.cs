namespace PurchaseAssistant.Application.DTOs.Operations;

public record DailyUsageIn(Guid ItemId, decimal QtyUsed, string Unit, DateOnly UsageDate, string? Notes = null);
public record DailyUsageOut(Guid Id, Guid ItemId, string? ItemName, decimal QtyUsed, string Unit, DateOnly UsageDate, DateTime CreatedAt);

public record ChecklistTemplateOut(Guid Id, string? Title, string? Description, string? Frequency);
public record ChecklistCompletionIn(Guid ChecklistId);
public record ChecklistCompletionOut(Guid Id, Guid ChecklistId, Guid UserId, DateTime CompletedAt);
