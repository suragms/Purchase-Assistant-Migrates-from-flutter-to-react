namespace PurchaseAssistant.Application.DTOs;

// ─── Draft ──────────────────────────────────────────────────
public record TradeDraftOut(Guid Id, int Step, string PayloadJson, DateTimeOffset CreatedAt, DateTimeOffset? UpdatedAt);
public record TradeDraftUpsertIn(int Step, string PayloadJson);

// ─── Preview & Validation ──────────────────────────────────
public record TradeLinePreviewIn(
    Guid? CatalogItemId, string ItemName, decimal Qty, string Unit,
    decimal? LandingCost, decimal? SellingRate, decimal? Discount,
    decimal? TaxPercent, string? TaxMode, decimal? WeightPerUnit,
    string? FreightType, decimal? FreightValue, decimal? DeliveredRate, decimal? BilltyRate,
    decimal? KgPerUnit, decimal? ItemsPerBox, decimal? WeightPerTin,
    int? PaymentDays
);

public record TradeLinePreviewOut(
    decimal LineTotal, decimal SellingSubtotal, decimal Profit,
    decimal TotalWeight, decimal? LandingCostPerKg, decimal? KgPerUnit
);

public record TradePurchasePreviewOut(
    List<TradeLinePreviewOut> Lines,
    decimal GrandTotal, decimal GrandSellingTotal, decimal GrandProfit,
    decimal TotalWeight
);

public record TradePurchaseValidateError(string Field, string Message);
public record TradePurchaseValidateOut(bool Valid, List<TradePurchaseValidateError> Errors);

public record TradeDuplicateCheckRequest(Guid SupplierId, decimal TotalAmount, DateOnly PurchaseDate);
public record TradeDuplicateCheckResponse(bool IsDuplicate, Guid? ExistingId, string? HumanId);

// ─── CRUD ──────────────────────────────────────────────────
public record TradePurchaseListOut(List<TradePurchaseListItemOut> Items, int TotalCount);

public record TradePurchaseListItemOut(
    Guid Id, string HumanId, string? InvoiceNumber,
    DateOnly? PurchaseDate, string SupplierName, Guid SupplierId,
    string? BrokerName, Guid? BrokerId,
    decimal TotalAmount, decimal? PaidAmount,
    string Status, bool IsDelivered, string DeliveryStatus,
    int LineCount, DateTimeOffset CreatedAt
);

public record TradePurchaseLineOut(
    Guid Id, Guid? CatalogItemId, string ItemName,
    decimal Qty, string Unit, string? UnitType,
    decimal LandingCost, decimal? SellingRate,
    decimal? LineTotal, decimal? Profit, decimal? TotalWeight,
    decimal? KgPerUnit, decimal? LandingCostPerKg,
    decimal? Discount, decimal? TaxPercent, string? TaxMode,
    string? FreightType, decimal? FreightValue,
    decimal? DeliveredRate, decimal? BilltyRate,
    decimal? ItemsPerBox, decimal? WeightPerTin,
    int? PaymentDays, string? HsnCode, string? ItemCode,
    string? Description, decimal? ReceivedQty, decimal? DamagedQty, decimal? ReturnQty,
    string? DefaultUnit, decimal? DefaultKgPerBag, string? DefaultPurchaseUnit,
    decimal LineLandingGross, decimal LineSellingGross, decimal? LineProfit
);

public record StockUpdateOut(
    Guid CatalogItemId, string Name, string? Unit,
    decimal OldQty, decimal NewQty, decimal Delta,
    bool NeedsUnitSetup, string? LineUnit
);

public record TradePurchaseOut(
    Guid Id, string HumanId, Guid BusinessId, Guid UserId,
    string? InvoiceNumber, DateOnly? PurchaseDate,
    Guid SupplierId, string SupplierName, string? SupplierPhone,
    string? SupplierGst, string? SupplierAddress,
    Guid? BrokerId, string? BrokerName, string? BrokerPhone,
    string? BrokerLocation, string? BrokerImageUrl,
    decimal TotalAmount, decimal? PaidAmount,
    decimal? Discount, decimal? CommissionPercent, string? CommissionMode, decimal? CommissionMoney,
    decimal? DeliveredRate, decimal? BilltyRate, decimal? FreightAmount, string? FreightType,
    int? PaymentDays, DateOnly? DueDate,
    string Status, string DerivedStatus, decimal Remaining,
    bool IsDelivered, string DeliveryStatus,
    DateTimeOffset? DeliveredAt, DateTimeOffset? DispatchedAt, DateTimeOffset? ArrivedAt,
    DateTimeOffset? StaffVerifiedAt, string? StaffVerifiedByName,
    DateTimeOffset? StockCommittedAt, DateTimeOffset? PaidAt,
    string? DispatchNote, string? TruckNumber, string? DriverContact,
    string? DeliveryNotes, decimal? StaffVerifiedQty, decimal? DeliveredQtyCommitted,
    decimal? TotalQty, decimal? TotalLandingSubtotal, decimal? TotalSellingSubtotal, decimal? TotalLineProfit,
    int ItemsCount, bool HasMissingDetails,
    string? CreatedByName, DateTimeOffset CreatedAt, DateTimeOffset? UpdatedAt,
    List<TradePurchaseLineOut> Lines,
    List<StockUpdateOut>? StockUpdates
);

public record TradePurchaseLineCreateIn(
    Guid? CatalogItemId, string ItemName, decimal Qty, string Unit,
    decimal? PurchaseRate, decimal? LandingCost,
    decimal? SellingRate, decimal? SellingCost,
    decimal? Discount, decimal? TaxPercent, string? TaxMode,
    string? FreightType, decimal? FreightValue,
    decimal? DeliveredRate, decimal? BilltyRate,
    decimal? WeightPerUnit, decimal? ItemsPerBox, decimal? WeightPerTin,
    decimal? KgPerUnit, decimal? LandingCostPerKg,
    int? PaymentDays, string? HsnCode, string? ItemCode,
    string? Description, string? BoxMode
);

public record TradePurchaseCreateIn(
    DateOnly PurchaseDate, Guid SupplierId, Guid? BrokerId,
    string? InvoiceNumber, int? PaymentDays,
    decimal? Discount, decimal? CommissionPercent, string? CommissionMode, decimal? CommissionMoney,
    decimal? DeliveredRate, decimal? BilltyRate, decimal? FreightAmount, string? FreightType,
    bool ForceDuplicate,
    string? Status,
    List<TradePurchaseLineCreateIn> Lines
);

public record TradePurchaseUpdateIn(
    DateOnly? PurchaseDate, Guid? SupplierId, Guid? BrokerId,
    string? InvoiceNumber, int? PaymentDays,
    decimal? Discount, decimal? CommissionPercent, string? CommissionMode, decimal? CommissionMoney,
    decimal? DeliveredRate, decimal? BilltyRate, decimal? FreightAmount, string? FreightType,
    bool ForceDuplicate,
    string? Status,
    List<TradePurchaseLineCreateIn> Lines
);

// ─── Next Human ID ─────────────────────────────────────────
public record NextHumanIdOut(string HumanId);

// ─── Last Defaults ─────────────────────────────────────────
public record TradeLastDefaultsOut(
    string Source, string? PurchaseId, string? PurchaseDate,
    Guid? BrokerId, string? SupplierName,
    int? PaymentDays, Guid? ItemId,
    string? Unit, decimal? PurchaseRate, decimal? LandingCost,
    decimal? LandingCostPerKg, decimal? SellingRate, decimal? SellingCost,
    decimal? WeightPerUnit, decimal? KgPerUnit,
    decimal? TaxPercent, decimal? DeliveredRate, decimal? BilltyRate,
    string? FreightType, decimal? FreightValue, decimal? FreightAmount,
    string? BoxMode, decimal? ItemsPerBox, decimal? WeightPerItem,
    decimal? KgPerBox, decimal? WeightPerTin
);

// ─── Delivery Pipeline ─────────────────────────────────────
public record DeliveryPipelineItemOut(
    Guid Id, string HumanId, string SupplierName, Guid SupplierId,
    string? BrokerName, Guid? BrokerId,
    decimal TotalAmount, string Status, bool IsDelivered, string DeliveryStatus,
    DateTimeOffset? DispatchedAt, DateTimeOffset? ArrivedAt,
    DateTimeOffset? DeliveredAt, DateTimeOffset? StockCommittedAt,
    DateTimeOffset? StaffVerifiedAt, string? StaffVerifiedByName,
    string? DispatchNote, string? TruckNumber, string? DriverContact,
    int LineCount, DateOnly? PurchaseDate
);

public record DeliveryPipelineCountsOut(
    int Pending, int Dispatched, int InTransit, int Arrived,
    int StaffVerifying, int StaffVerified, int Partial,
    int StockCommitted, int Cancelled,
    decimal TotalPendingAmount
);

public record DeliveryUpdateIn(string? DispatchNote, string? TruckNumber, string? DriverContact);
public record DeliveryDispatchIn(string? DispatchNote, string? TruckNumber, string? DriverContact, bool MarkInTransit);
public record DeliveryArriveIn(string? Notes, string? TruckNumber, string? DriverContact, decimal? DamageQty, decimal? MissingQty, bool? BrokerConfirmed);
public record DeliveryVerifyLineIn(Guid LineId, decimal ReceivedQty, decimal DamagedQty, decimal ReturnQty);
public record DeliveryVerifyIn(List<DeliveryVerifyLineIn> Lines, string? Notes);

// ─── Payment ───────────────────────────────────────────────
public record PaymentUpdateIn(decimal PaidAmount, DateTimeOffset? PaidAt);
public record MarkPaidIn(decimal? PaidAmount, DateTimeOffset? PaidAt);
public record CancelIn(string? Reason);

// ─── Lifecycle Events ──────────────────────────────────────
public record PurchaseLifecycleEventOut(
    Guid Id, Guid PurchaseId, Guid BusinessId,
    string? FromStatus, string ToStatus,
    Guid? ActorId, string? ActorName,
    string? Notes, DateTimeOffset CreatedAt
);

public record LifecycleEventCreateIn(string ToStatus, string? Notes);

// ─── Damage Reports ────────────────────────────────────────
public record PurchaseDamageReportOut(
    Guid Id, Guid PurchaseId, Guid BusinessId,
    Guid? CatalogItemId, string ItemName,
    decimal QtyDamaged, string? Unit,
    string DamageType, string? Reason,
    string Status, string? PhotoUrl, string? Notes,
    Guid? ReportedByUserId, string? ReporterName,
    DateTimeOffset CreatedAt
);

public record DamageReportCreateIn(
    Guid? CatalogItemId, string ItemName,
    decimal QtyDamaged, string? Unit,
    string DamageType, string? Reason,
    string? PhotoUrl, string? Notes,
    bool EmitNotification, int? DamagedItemsInBatch
);

public record DamageReportUpdateIn(string Status, string? Notes);

public record DamagePendingCountOut(int PendingCount);
