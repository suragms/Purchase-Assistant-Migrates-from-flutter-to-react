namespace PurchaseAssistant.Application.DTOs.Operations;

public class DailyUsageDto
{
    public Guid Id { get; set; }
    public Guid CatalogItemId { get; set; }
    public string ItemName { get; set; } = string.Empty;
    public decimal QtyUsed { get; set; }
    public string Unit { get; set; } = string.Empty;
    public DateOnly UsageDate { get; set; }
    public string? Notes { get; set; }
    public string? RecordedByName { get; set; }
    public DateTimeOffset CreatedAt { get; set; }
}

public class DailyUsageCreateRequest
{
    public Guid CatalogItemId { get; set; }
    public decimal QtyUsed { get; set; }
    public string Unit { get; set; } = string.Empty;
    public DateOnly UsageDate { get; set; }
    public string? Notes { get; set; }
}

public class ChecklistTemplateDto
{
    public Guid Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public List<ChecklistTask> Tasks { get; set; } = new();
    public DateTimeOffset CreatedAt { get; set; }
}

public class ChecklistTask
{
    public string Title { get; set; } = string.Empty;
    public bool IsRequired { get; set; }
}

public class ChecklistCompletionDto
{
    public Guid Id { get; set; }
    public Guid TemplateId { get; set; }
    public string TemplateName { get; set; } = string.Empty;
    public List<ChecklistTaskResult> Results { get; set; } = new();
    public string? CompletedByName { get; set; }
    public DateTimeOffset CompletedAt { get; set; }
}

public class ChecklistTaskResult
{
    public string Title { get; set; } = string.Empty;
    public bool IsDone { get; set; }
    public string? Notes { get; set; }
}

public class ChecklistCompletionCreateRequest
{
    public Guid TemplateId { get; set; }
    public List<ChecklistTaskResult> Results { get; set; } = new();
    public string? Notes { get; set; }
}
