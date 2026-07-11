namespace PurchaseAssistant.Application.DTOs.Reports;

public class TradeReportRequest
{
    public DateTime? From { get; set; }
    public DateTime? To { get; set; }
    public Guid? SupplierId { get; set; }
    public Guid? BrokerId { get; set; }
    public Guid? CategoryId { get; set; }
    public string? Status { get; set; }
    public int Page { get; set; } = 1;
    public int PageSize { get; set; } = 20;
}

public class TradeReportResponse
{
    public List<TradeReportRow> Rows { get; set; } = new();
    public int TotalCount { get; set; }
    public decimal GrandTotal { get; set; }
}

public class TradeReportRow
{
    public Guid PurchaseId { get; set; }
    public string HumanId { get; set; } = string.Empty;
    public DateOnly? PurchaseDate { get; set; }
    public string SupplierName { get; set; } = string.Empty;
    public decimal TotalAmount { get; set; }
    public decimal? PaidAmount { get; set; }
    public string Status { get; set; } = string.Empty;
    public int LineCount { get; set; }
}

public class ReportSavedViewDto
{
    public Guid Id { get; set; }
    public string Name { get; set; } = string.Empty;
    public string ReportType { get; set; } = string.Empty;
    public string FiltersJson { get; set; } = string.Empty;
    public DateTimeOffset CreatedAt { get; set; }
}

public class ReportSavedViewCreateRequest
{
    public string Name { get; set; } = string.Empty;
    public string ReportType { get; set; } = string.Empty;
    public string FiltersJson { get; set; } = string.Empty;
}

public class ReportSavedViewUpdateRequest
{
    public string? Name { get; set; }
    public string? FiltersJson { get; set; }
}
