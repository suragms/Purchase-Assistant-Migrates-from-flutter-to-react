namespace PurchaseAssistant.Application.DTOs.Search;

public record UnifiedSearchOut(List<SearchResult> Results);
public record SearchResult(string Type, Guid Id, string Name, string? Detail);
