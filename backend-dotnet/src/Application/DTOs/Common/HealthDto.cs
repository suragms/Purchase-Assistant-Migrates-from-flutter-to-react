namespace PurchaseAssistant.Application.DTOs.Common;

public class HealthResponse
{
    public string Status { get; set; } = string.Empty;
    public DateTimeOffset Timestamp { get; set; }
    public HealthDbCheckResponse? Database { get; set; }
}

public class HealthLiveResponse
{
    public string Status { get; set; } = "ok";
}

public class HealthReadyResponse
{
    public string Status { get; set; } = string.Empty;
    public bool Database { get; set; }
}

public class HealthDbCheckResponse
{
    public bool Connected { get; set; }
    public long? LatencyMs { get; set; }
    public string? Error { get; set; }
}
