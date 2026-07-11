namespace PurchaseAssistant.Application.DTOs;

public record SupplierResponse(Guid Id, string Name, string? Phone, string? City, string? Notes, decimal? OutstandingBalance);
public record CreateSupplierRequest(string Name, string? Phone, string? City, string? Notes);
public record BrokerResponse(Guid Id, string Name, string? Phone, string? City, string? CommissionType, decimal? CommissionValue, string? Notes, decimal? OutstandingBalance);
public record CreateBrokerRequest(string Name, string? Phone, string? City, string? CommissionType, decimal? CommissionValue, string? Notes);
