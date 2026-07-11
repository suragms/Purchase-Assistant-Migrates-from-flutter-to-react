using PurchaseAssistant.Application.DTOs;

namespace PurchaseAssistant.Application.Services;

public interface ITradePurchaseService
{
    // ─── Draft ──────────────────────────────────────────────
    Task<TradeDraftOut?> GetDraftAsync(Guid businessId, Guid userId, CancellationToken ct = default);
    Task<TradeDraftOut> UpsertDraftAsync(Guid businessId, Guid userId, int step, string payloadJson, CancellationToken ct = default);
    Task DeleteDraftAsync(Guid businessId, Guid userId, CancellationToken ct = default);

    // ─── Preview / Validate ─────────────────────────────────
    Task<TradePurchasePreviewOut> PreviewLinesAsync(Guid businessId, TradePurchaseCreateIn request, CancellationToken ct = default);
    Task<TradePurchaseValidateOut> ValidatePurchaseAsync(Guid businessId, TradePurchaseCreateIn request, CancellationToken ct = default);
    Task<TradeDuplicateCheckResponse> CheckDuplicateAsync(Guid businessId, TradeDuplicateCheckRequest request, CancellationToken ct = default);

    // ─── Next Human ID ──────────────────────────────────────
    Task<NextHumanIdOut> GetNextHumanIdAsync(Guid businessId, CancellationToken ct = default);

    // ─── List ───────────────────────────────────────────────
    Task<TradePurchaseListOut> ListPurchasesAsync(Guid businessId, int limit, int offset, string? status, string? q, Guid? supplierId, Guid? brokerId, Guid? catalogItemId, DateOnly? purchaseFrom, DateOnly? purchaseTo, bool includeLines, string actorRole, CancellationToken ct = default);

    // ─── Last Defaults ──────────────────────────────────────
    Task<TradeLastDefaultsOut> GetLastDefaultsAsync(Guid businessId, Guid catalogItemId, Guid? supplierId, Guid? brokerId, CancellationToken ct = default);

    // ─── CRUD ───────────────────────────────────────────────
    Task<TradePurchaseOut> CreatePurchaseAsync(Guid businessId, Guid userId, TradePurchaseCreateIn request, string? idempotencyKey, CancellationToken ct = default);
    Task<TradePurchaseOut?> GetPurchaseAsync(Guid businessId, Guid purchaseId, CancellationToken ct = default);
    Task<TradePurchaseOut> UpdatePurchaseAsync(Guid businessId, Guid purchaseId, TradePurchaseUpdateIn request, CancellationToken ct = default);
    Task<bool> DeletePurchaseAsync(Guid businessId, Guid purchaseId, CancellationToken ct = default);

    // ─── Payment ────────────────────────────────────────────
    Task<TradePurchaseOut?> UpdatePaymentAsync(Guid businessId, Guid purchaseId, PaymentUpdateIn request, CancellationToken ct = default);
    Task<TradePurchaseOut?> MarkPaidAsync(Guid businessId, Guid purchaseId, MarkPaidIn request, CancellationToken ct = default);
    Task<TradePurchaseOut?> CancelPurchaseAsync(Guid businessId, Guid purchaseId, CancellationToken ct = default);

    // ─── Delivery Pipeline ──────────────────────────────────
    Task<DeliveryPipelineCountsOut> GetDeliveryPipelineAsync(Guid businessId, CancellationToken ct = default);

    // ─── Delivery Actions ───────────────────────────────────
    Task<TradePurchaseOut?> PatchDeliveryAsync(Guid businessId, Guid purchaseId, DeliveryUpdateIn request, CancellationToken ct = default);
    Task<TradePurchaseOut?> DispatchAsync(Guid businessId, Guid purchaseId, DeliveryDispatchIn request, Guid userId, string userName, CancellationToken ct = default);
    Task<TradePurchaseOut?> ArriveAsync(Guid businessId, Guid purchaseId, DeliveryArriveIn request, Guid userId, string userName, CancellationToken ct = default);
    Task<TradePurchaseOut?> CommitStockAsync(Guid businessId, Guid purchaseId, Guid userId, string userName, CancellationToken ct = default);
    Task<TradePurchaseOut?> AutoCommitAsync(Guid businessId, Guid purchaseId, Guid userId, string userName, CancellationToken ct = default);
    Task<TradePurchaseOut?> VerifyDeliveryAsync(Guid businessId, Guid purchaseId, DeliveryVerifyIn request, Guid userId, string userName, CancellationToken ct = default);

    // ─── Lifecycle Events ───────────────────────────────────
    Task<List<PurchaseLifecycleEventOut>> ListLifecycleEventsAsync(Guid businessId, Guid purchaseId, CancellationToken ct = default);
    Task<TradePurchaseOut?> TransitionLifecycleAsync(Guid businessId, Guid purchaseId, string toStatus, Guid userId, string? notes, CancellationToken ct = default);
}
