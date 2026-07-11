namespace PurchaseAssistant.Application.DTOs.Contacts;

// Suppliers
public record SupplierCreate(string Name, string? Phone = null, string? Location = null, Guid? BrokerId = null, string? FreightType = null, List<Guid>? BrokerIds = null);
public record SupplierUpdate(string? Name = null, string? Phone = null, string? Location = null, string? FreightType = null, List<Guid>? BrokerIds = null);
public record SupplierOut(Guid Id, string Name, string? Phone, string? Location, string? GstNumber, string? FreightType, DateTime CreatedAt, List<Guid>? BrokerIds);
public record SupplierOutCompact(Guid Id, string Name, string? Phone, string? Location);
public record SupplierMetricsOut(int Deals, decimal? TotalQty, decimal? AvgLanding, decimal? TotalProfit, decimal? Margin);

// Brokers
public record BrokerCreate(string Name, string? Phone = null, string? Location = null, string? CommissionType = "percent", decimal? CommissionValue = null, List<Guid>? SupplierIds = null);
public record BrokerUpdate(string? Name = null, string? Phone = null, string? Location = null, string? CommissionType = null, decimal? CommissionValue = null, List<Guid>? SupplierIds = null);
public record BrokerOut(Guid Id, string Name, string? Phone, string? Location, string? CommissionType, decimal? CommissionValue, DateTime CreatedAt, List<Guid>? SupplierIds);
public record BrokerMetricsOut(int Deals, decimal? TotalCommission, decimal? TotalProfit);
public record LinkedSupplierOut(Guid Id, string Name);

// Search
public record ContactSearchOut(List<SearchResult> Results);
public record SearchResult(string Type, Guid Id, string Name, string? Detail);
public record CategoryItemRow(Guid ItemId, string ItemName, string CategoryName, decimal? LineTotal, decimal? TotalQty, decimal? TotalWeightKg);
