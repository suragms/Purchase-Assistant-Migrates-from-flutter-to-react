namespace PurchaseAssistant.Application.DTOs.Media;

public record OcrRequest(string ImageData, string? ContentType = null);
public record OcrResponse(string Text, List<OcrLineItem>? LineItems = null);
public record OcrLineItem(string Name, decimal? Qty, string? Unit, decimal? Rate, decimal? Amount);
