namespace PurchaseAssistant.Application.DTOs;

public record BusinessResponse(Guid Id, string Name, string? BrandingTitle, string? BrandingLogoUrl, string? GstNumber, string? Address, string? Phone, string? ContactEmail, DateTimeOffset CreatedAt);
public record CreateBusinessRequest(string Name, string? GstNumber, string? Address, string? Phone, string? ContactEmail);
public record UpdateBusinessRequest(string? Name, string? BrandingTitle, string? BrandingLogoUrl, string? GstNumber, string? Address, string? Phone, string? ContactEmail);
