using System.Text.Json;

namespace PurchaseAssistant.Application.DTOs.Trade;

public record TradePurchaseLineIn(
    Guid CatalogItemId, string ItemName, decimal Qty, string Unit, decimal LandingCost,
    decimal? PurchaseRate = null, decimal? KgPerUnit = null, decimal? LandingCostPerKg = null,
    decimal? SellingCost = null, decimal? SellingRate = null,
    string? FreightType = null, decimal? FreightValue = null,
    string? BoxMode = null, decimal? ItemsPerBox = null, decimal? WeightPerItem = null,
    decimal? Discount = null, decimal? TaxPercent = null, string? TaxMode = "exclusive",
    int? PaymentDays = null, string? HsnCode = null);

public record TradePurchaseCreateRequest(
    DateOnly PurchaseDate, Guid SupplierId,
    string? InvoiceNumber = null, Guid? BrokerId = null, bool ForceDuplicate = false,
    string Status = "confirmed", int? PaymentDays = null, decimal? Discount = null,
    decimal? CommissionPercent = null, string CommissionMode = "percent",
    decimal? CommissionMoney = null, decimal? DeliveredRate = null, decimal? BilltyRate = null,
    decimal? FreightAmount = null, string? FreightType = null,
    List<TradePurchaseLineIn>? Lines = null);

public record TradePurchaseUpdateRequest(
    DateOnly PurchaseDate, Guid SupplierId,
    string? InvoiceNumber = null, Guid? BrokerId = null, bool ForceDuplicate = false,
    string Status = "confirmed", int? PaymentDays = null, decimal? Discount = null,
    decimal? CommissionPercent = null, string CommissionMode = "percent",
    decimal? CommissionMoney = null, decimal? DeliveredRate = null, decimal? BilltyRate = null,
    decimal? FreightAmount = null, string? FreightType = null,
    List<TradePurchaseLineIn>? Lines = null);

public record TradePurchaseLineOut(
    Guid Id, Guid CatalogItemId, string ItemName, decimal Qty, string Unit,
    decimal LandingCost, decimal? KgPerUnit, decimal? LandingCostPerKg,
    decimal? SellingCost, decimal? SellingRate, decimal? LineTotal, decimal? Profit,
    decimal? Discount, decimal? TaxPercent, string? TaxMode);

public record TradePurchaseOut(
    Guid Id, string HumanId, DateOnly PurchaseDate,
    Guid SupplierId, Guid? BrokerId,
    decimal? TotalAmount, decimal PaidAmount, decimal? Discount,
    string Status, string? DeliveryStatus,
    DateTime CreatedAt, DateTime? UpdatedAt,
    List<TradePurchaseLineOut> Lines);

public record TradePurchaseListItemOut(
    Guid Id, string HumanId, DateOnly PurchaseDate,
    Guid SupplierId, Guid? BrokerId,
    decimal? TotalAmount, decimal PaidAmount, decimal? Discount,
    string Status, string? DeliveryStatus,
    DateTime CreatedAt, DateTime? UpdatedAt,
    List<TradePurchaseLineOut> Lines);

public record TradeDraftUpsertRequest(int Step, Dictionary<string, object> Payload);
public record TradeDraftOut(int Step, Dictionary<string, object> Payload, DateTime UpdatedAt);

public record TradePurchasePreviewOut(decimal TotalQty, decimal TotalAmount, List<TradePurchasePreviewLineOut> Lines);
public record TradePurchasePreviewLineOut(int Index, decimal LineTotal, decimal LineLandingGross, decimal? LineProfit, decimal LineTotalWeightKg);
public record TradePurchaseValidateOut(bool Ok, List<Dictionary<string, object>> Errors, List<Dictionary<string, object>> Warnings);

public record TradeDuplicateCheckRequest(Guid? SupplierId, DateOnly PurchaseDate, decimal TotalAmount, List<TradePurchaseLineIn>? Lines = null);
public record TradeDuplicateCheckResponse(bool Duplicate, string? Message, Guid? ExistingId, string? ExistingHumanId);
public record TradeNextHumanIdOut(string HumanId);

public record TradePurchaseDeliveryPatch(bool IsDelivered, DateTime? DeliveredAt = null, string? DeliveryNotes = null);
public record TradePurchaseVerifyIn(List<TradePurchaseVerificationLineIn> Lines, string? Notes = null);
public record TradePurchaseVerificationLineIn(Guid LineId, decimal ReceivedQty, decimal DamagedQty = 0, decimal ReturnQty = 0);
public record TradePurchaseDispatchIn(string? TruckNumber = null, string? DriverContact = null, string? DispatchNote = null, bool MarkInTransit = false);
public record TradePurchaseArriveIn(string? Notes = null, string? TruckNumber = null, string? DriverContact = null);

public record TradePurchasePaymentPatch(decimal PaidAmount, DateTime? PaidAt = null);
public record TradeMarkPaidRequest(decimal? PaidAmount = null, DateTime? PaidAt = null);

public record TradePurchaseDeliveryPipelineOut(
    int Pending = 0, int Dispatched = 0, int InTransit = 0, int Arrived = 0,
    int StaffVerifying = 0, int StaffVerified = 0, int Partial = 0,
    int StockCommitted = 0, int Cancelled = 0, decimal TotalPendingAmount = 0);

public record PurchaseLifecycleTransitionIn(string ToStatus, string? Notes = null, Dictionary<string, object>? Metadata = null);
public record PurchaseLifecycleEventOut(Guid Id, Guid PurchaseId, Guid? BusinessId, string? FromStatus, string ToStatus, Guid? ActorId, string? ActorName, string? Notes, Dictionary<string, object>? Metadata, DateTime CreatedAt);

public record PurchaseDamageReportIn(
    Guid? TradePurchaseId, Guid? CatalogItemId, string? ItemName,
    decimal? QtyDamaged, string? Unit, string? DamageType,
    string? Reason, string? PhotoUrl = null, string? Notes = null);
public record PurchaseDamageReportOut(
    Guid Id, Guid? TradePurchaseId, Guid? CatalogItemId,
    string? ItemName, decimal? QtyDamaged, string? Unit,
    string? DamageType, string Status, string? Reason,
    string? Notes, DateTime CreatedAt);
public record PurchaseDamageReportStatusPatch(string Status, string? ResolutionNotes = null);
public record PendingDamageReportsCountOut(int Count);

public record StockUpdateOut(Guid CatalogItemId, string Name, decimal OldQty, decimal NewQty, decimal Delta);
