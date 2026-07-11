namespace PurchaseAssistant.Application.DTOs.Reports;

public record TradeReportOut(Dictionary<string, object> Data);
public record ReportSavedViewOut(Guid Id, string Name, string ReportType, Dictionary<string, object>? Filters, DateTime CreatedAt);
public record ReportSavedViewIn(string Name, string ReportType, Dictionary<string, object>? Filters = null);
public record ReportSavedViewUpdate(string? Name = null, string? ReportType = null, Dictionary<string, object>? Filters = null);
