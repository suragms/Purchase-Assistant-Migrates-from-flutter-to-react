namespace PurchaseAssistant.Application.DTOs.Exports;

public record BackupRequest(bool IncludePurchases = true, bool IncludeStock = true, bool IncludeLedgers = true);
