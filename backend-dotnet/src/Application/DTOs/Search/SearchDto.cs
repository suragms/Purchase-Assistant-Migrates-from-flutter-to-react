namespace PurchaseAssistant.Application.DTOs.Search;

public class UnifiedSearchRequest
{
    public string Query { get; set; } = string.Empty;
    public List<string> EntityTypes { get; set; } = new();
    public int? Limit { get; set; }
}

public class UnifiedSearchResponse
{
    public List<SearchHit> Hits { get; set; } = new();
    public int TotalCount { get; set; }
}

public class SearchHit
{
    public string EntityType { get; set; } = string.Empty;
    public Guid EntityId { get; set; }
    public string DisplayName { get; set; } = string.Empty;
    public string? Subtitle { get; set; }
    public double Score { get; set; }
}
