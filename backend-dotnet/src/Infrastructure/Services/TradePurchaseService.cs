using Microsoft.EntityFrameworkCore;
using PurchaseAssistant.Application.DTOs;
using PurchaseAssistant.Application.Services;
using PurchaseAssistant.Domain.Entities.Catalog;
using PurchaseAssistant.Domain.Entities.Contacts;
using PurchaseAssistant.Domain.Entities.Trade;
using PurchaseAssistant.Domain.Entities.Stock;
using PurchaseAssistant.Infrastructure.Data;

namespace PurchaseAssistant.Infrastructure.Services;

public class TradePurchaseService : ITradePurchaseService
{
    private readonly PurchaseAssistantDbContext _db;

    public TradePurchaseService(PurchaseAssistantDbContext db) => _db = db;

    // ─── Draft ─────────────────────────────────────────────────

    public async Task<TradeDraftOut?> GetDraftAsync(Guid businessId, Guid userId, CancellationToken ct)
    {
        var d = await _db.TradePurchaseDrafts
            .Where(x => x.BusinessId == businessId && x.UserId == userId)
            .OrderByDescending(x => x.CreatedAt)
            .FirstOrDefaultAsync(ct);
        if (d == null) return null;
        var step = int.TryParse(d.Step, out var s) ? s : 0;
        return new TradeDraftOut(d.Id, step, d.Payload ?? "{}", d.CreatedAt, d.CreatedAt);
    }

    public async Task<TradeDraftOut> UpsertDraftAsync(Guid businessId, Guid userId, int step, string payloadJson, CancellationToken ct)
    {
        var existing = await _db.TradePurchaseDrafts
            .Where(x => x.BusinessId == businessId && x.UserId == userId)
            .FirstOrDefaultAsync(ct);

        if (existing != null)
        {
            existing.Step = step.ToString();
            existing.Payload = payloadJson;
        }
        else
        {
            existing = new TradePurchaseDraft
            {
                BusinessId = businessId,
                UserId = userId,
                Step = step.ToString(),
                Payload = payloadJson,
            };
            _db.TradePurchaseDrafts.Add(existing);
        }
        await _db.SaveChangesAsync(ct);
        return new TradeDraftOut(existing.Id, step, payloadJson, existing.CreatedAt, existing.CreatedAt);
    }

    public async Task DeleteDraftAsync(Guid businessId, Guid userId, CancellationToken ct)
    {
        var drafts = await _db.TradePurchaseDrafts
            .Where(x => x.BusinessId == businessId && x.UserId == userId)
            .ToListAsync(ct);
        _db.TradePurchaseDrafts.RemoveRange(drafts);
        await _db.SaveChangesAsync(ct);
    }

    // ─── Preview ───────────────────────────────────────────────

    public async Task<TradePurchasePreviewOut> PreviewLinesAsync(Guid businessId, TradePurchaseCreateIn request, CancellationToken ct)
    {
        var lines = request.Lines ?? [];
        var previews = new List<TradeLinePreviewOut>();

        foreach (var line in lines)
        {
            var lineTotal = (line.LandingCost ?? 0) * line.Qty;
            var sellingSubtotal = (line.SellingRate ?? 0) * line.Qty;
            var profit = sellingSubtotal - lineTotal;
            var weight = (line.KgPerUnit ?? 0) * line.Qty;
            var costPerKg = weight > 0 ? lineTotal / weight : (decimal?)null;

            previews.Add(new TradeLinePreviewOut(lineTotal, sellingSubtotal, profit, weight, costPerKg, line.KgPerUnit));
        }

        return new TradePurchasePreviewOut(previews, previews.Sum(l => l.LineTotal), previews.Sum(l => l.SellingSubtotal), previews.Sum(l => l.Profit), previews.Sum(l => l.TotalWeight));
    }

    // ─── Validate ──────────────────────────────────────────────

    public async Task<TradePurchaseValidateOut> ValidatePurchaseAsync(Guid businessId, TradePurchaseCreateIn request, CancellationToken ct)
    {
        var errors = new List<TradePurchaseValidateError>();

        if (request.SupplierId == Guid.Empty)
            errors.Add(new TradePurchaseValidateError("supplierId", "Supplier is required"));

        if (request.Lines == null || request.Lines.Count == 0)
            errors.Add(new TradePurchaseValidateError("lines", "At least one line is required"));
        else
        {
            for (int i = 0; i < request.Lines.Count; i++)
            {
                var l = request.Lines[i];
                if (l.Qty <= 0) errors.Add(new TradePurchaseValidateError($"lines[{i}].qty", "Qty must be positive"));
                if (l.LandingCost <= 0) errors.Add(new TradePurchaseValidateError($"lines[{i}].landingCost", "Landing cost must be positive"));
            }
        }

        return new TradePurchaseValidateOut(errors.Count == 0, errors);
    }

    // ─── Duplicate Check ───────────────────────────────────────

    public async Task<TradeDuplicateCheckResponse> CheckDuplicateAsync(Guid businessId, TradeDuplicateCheckRequest request, CancellationToken ct)
    {
        var existing = await _db.TradePurchases
            .Where(tp => tp.BusinessId == businessId
                && tp.SupplierId == request.SupplierId
                && tp.PurchaseDate == request.PurchaseDate
                && Math.Abs((decimal)(tp.TotalAmount ?? 0) - request.TotalAmount) < 1
                && tp.DeletedAt == null)
            .Select(tp => new { tp.Id, tp.HumanId })
            .FirstOrDefaultAsync(ct);

        if (existing != null)
            return new TradeDuplicateCheckResponse(true, existing.Id, existing.HumanId);

        return new TradeDuplicateCheckResponse(false, null, null);
    }

    // ─── Next Human ID ─────────────────────────────────────────

    public async Task<NextHumanIdOut> GetNextHumanIdAsync(Guid businessId, CancellationToken ct)
    {
        var count = await _db.TradePurchases
            .CountAsync(tp => tp.BusinessId == businessId, ct);

        var prefix = $"PO-{DateTime.UtcNow:yyMMdd}-";
        return new NextHumanIdOut($"{prefix}{count + 1}");
    }

    // ─── List ──────────────────────────────────────────────────

    public async Task<TradePurchaseListOut> ListPurchasesAsync(
        Guid businessId, int limit, int offset, string? status, string? q,
        Guid? supplierId, Guid? brokerId, Guid? catalogItemId,
        DateOnly? purchaseFrom, DateOnly? purchaseTo, bool includeLines, string actorRole, CancellationToken ct)
    {
        var query = _db.TradePurchases
            .Where(tp => tp.BusinessId == businessId && tp.DeletedAt == null);

        if (!string.IsNullOrWhiteSpace(status))
            query = query.Where(tp => tp.Status == status);

        if (supplierId.HasValue)
            query = query.Where(tp => tp.SupplierId == supplierId.Value);

        if (brokerId.HasValue)
            query = query.Where(tp => tp.BrokerId == brokerId.Value);

        if (purchaseFrom.HasValue)
            query = query.Where(tp => tp.PurchaseDate >= purchaseFrom.Value);

        if (purchaseTo.HasValue)
            query = query.Where(tp => tp.PurchaseDate <= purchaseTo.Value);

        if (!string.IsNullOrWhiteSpace(q))
        {
            var search = q.Trim().ToLower();
            query = query.Where(tp => tp.HumanId.ToLower().Contains(search));
        }

        var totalCount = await query.CountAsync(ct);

        var rows = await query
            .OrderByDescending(tp => tp.PurchaseDate)
            .ThenByDescending(tp => tp.CreatedAt)
            .Skip(offset)
            .Take(limit)
            .ToListAsync(ct);

        var supplierIds = rows.Where(r => r.SupplierId != Guid.Empty).Select(r => r.SupplierId).Distinct().ToHashSet();
        var brokerIds = rows.Where(r => r.BrokerId.HasValue).Select(r => r.BrokerId!.Value).Distinct().ToHashSet();

        var sNames = await _db.Suppliers.Where(s => supplierIds.Contains(s.Id)).ToDictionaryAsync(s => s.Id, s => s.Name, ct);
        var bNames = await _db.Brokers.Where(b => brokerIds.Contains(b.Id)).ToDictionaryAsync(b => b.Id, b => b.Name, ct);

        var lineCounts = includeLines
            ? await _db.TradePurchaseLines
                .Where(l => rows.Select(r => r.Id).Contains(l.TradePurchaseId))
                .GroupBy(l => l.TradePurchaseId)
                .ToDictionaryAsync(g => g.Key, g => g.Count(), ct)
            : new Dictionary<Guid, int>();

        var items = rows.Select(tp =>
        {
            var sName = tp.SupplierId.HasValue ? sNames.GetValueOrDefault(tp.SupplierId.Value) : null;
            var bName = tp.BrokerId.HasValue ? bNames.GetValueOrDefault(tp.BrokerId.Value) : null;
            return new TradePurchaseListItemOut(
                Id: tp.Id, HumanId: tp.HumanId, InvoiceNumber: null,
                PurchaseDate: tp.PurchaseDate, SupplierName: sName ?? "Unknown", SupplierId: tp.SupplierId ?? Guid.Empty,
                BrokerName: bName, BrokerId: tp.BrokerId,
                TotalAmount: tp.TotalAmount ?? 0, PaidAmount: tp.PaidAmount,
                Status: tp.Status, IsDelivered: tp.DeliveryStatus == "delivered", DeliveryStatus: tp.DeliveryStatus ?? "pending",
                LineCount: includeLines ? lineCounts.GetValueOrDefault(tp.Id) : 0,
                CreatedAt: tp.CreatedAt
            );
        }).ToList();

        return new TradePurchaseListOut(items, totalCount);
    }

    // ─── Last Defaults ─────────────────────────────────────────

    public async Task<TradeLastDefaultsOut> GetLastDefaultsAsync(Guid businessId, Guid catalogItemId, Guid? supplierId, Guid? brokerId, CancellationToken ct)
    {
        var lastLine = await _db.TradePurchaseLines
            .Where(l => l.CatalogItemId == catalogItemId)
            .Join(_db.TradePurchases.Where(tp => tp.BusinessId == businessId && tp.DeletedAt == null),
                l => l.TradePurchaseId, tp => tp.Id,
                (l, tp) => new { Line = l, Purchase = tp })
            .OrderByDescending(x => x.Purchase.PurchaseDate)
            .FirstOrDefaultAsync(ct);

        if (lastLine == null)
            return new TradeLastDefaultsOut("none", null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null, null);

        return new TradeLastDefaultsOut(
            Source: "last_purchase",
            PurchaseId: lastLine.Purchase.HumanId,
            PurchaseDate: lastLine.Purchase.PurchaseDate.ToString(),
            BrokerId: lastLine.Purchase.BrokerId,
            SupplierName: null,
            PaymentDays: lastLine.Purchase.PaymentDays,
            ItemId: lastLine.Line.CatalogItemId,
            Unit: lastLine.Line.Unit,
            PurchaseRate: null,
            LandingCost: lastLine.Line.LandingCost,
            LandingCostPerKg: lastLine.Line.LandingCostPerKg,
            SellingRate: lastLine.Line.SellingRate,
            SellingCost: null,
            WeightPerUnit: lastLine.Line.KgPerUnit,
            KgPerUnit: lastLine.Line.KgPerUnit,
            TaxPercent: lastLine.Line.TaxPercent,
            DeliveredRate: null,
            BilltyRate: null,
            FreightType: lastLine.Purchase.FreightType,
            FreightValue: null,
            FreightAmount: null,
            BoxMode: null,
            ItemsPerBox: null,
            WeightPerItem: null,
            KgPerBox: null,
            WeightPerTin: null
        );
    }

    // ─── Create ────────────────────────────────────────────────

    public async Task<TradePurchaseOut> CreatePurchaseAsync(Guid businessId, Guid userId, TradePurchaseCreateIn request, string? idempotencyKey, CancellationToken ct)
    {
        if (!string.IsNullOrWhiteSpace(idempotencyKey))
        {
            var existing = await _db.TradePurchases
                .FirstOrDefaultAsync(tp => tp.BusinessId == businessId && tp.HumanId == idempotencyKey, ct);
            if (existing != null)
                return await BuildPurchaseOutAsync(businessId, existing.Id, ct);
        }

        var humanId = (await GetNextHumanIdAsync(businessId, ct)).HumanId;

        var purchase = new TradePurchase
        {
            BusinessId = businessId,
            UserId = userId,
            HumanId = humanId,
            PurchaseDate = request.PurchaseDate,
            SupplierId = request.SupplierId,
            BrokerId = request.BrokerId,
            Status = request.Status ?? "draft",
            PaymentDays = request.PaymentDays,
            Discount = request.Discount,
            CommissionType = request.CommissionMode,
            CommissionValue = request.CommissionPercent,
            CommissionMoney = request.CommissionMoney,
            FreightCharge = request.FreightAmount,
            FreightType = request.FreightType,
            Notes = null,
        };

        _db.TradePurchases.Add(purchase);
        await _db.SaveChangesAsync(ct);

        if (request.Lines != null)
        {
            foreach (var line in request.Lines)
            {
                var kgPerUnit = line.KgPerUnit;
                var totalWeight = kgPerUnit.HasValue ? kgPerUnit.Value * line.Qty : (decimal?)null;
                var lineTotal = (line.LandingCost ?? 0) * line.Qty;
                var sellingTotal = line.SellingRate.HasValue ? line.SellingRate.Value * line.Qty : (decimal?)null;
                var profit = sellingTotal.HasValue ? sellingTotal - lineTotal : (decimal?)null;
                var costPerKg = totalWeight.HasValue && totalWeight.Value > 0 ? lineTotal / totalWeight.Value : (decimal?)null;

                _db.TradePurchaseLines.Add(new TradePurchaseLine
                {
                    TradePurchaseId = purchase.Id,
                    CatalogItemId = line.CatalogItemId,
                    ItemName = line.ItemName,
                    Qty = line.Qty,
                    Unit = line.Unit ?? "kg",
                    LandingCost = line.LandingCost ?? 0,
                    SellingRate = line.SellingRate,
                    LineTotal = lineTotal,
                    Profit = profit,
                    KgPerUnit = kgPerUnit,
                    TotalWeight = totalWeight,
                    LandingCostPerKg = costPerKg,
                    DiscountPct = line.Discount,
                    TaxPercent = line.TaxPercent,
                    TaxMode = line.TaxMode,
                });

                if (line.CatalogItemId.HasValue)
                {
                    var catItem = await _db.CatalogItems.FindAsync(new object[] { line.CatalogItemId.Value }, ct);
                    if (catItem != null)
                    {
                        catItem.LastPurchasePrice = line.LandingCost;
                        catItem.LastSellingRate = line.SellingRate;
                        catItem.LastLineQty = line.Qty;
                        catItem.LastLineUnit = line.Unit;
                        catItem.LastLineWeightKg = totalWeight;
                        catItem.LastSupplierId = request.SupplierId;
                        catItem.LastBrokerId = request.BrokerId;
                        catItem.LastTradePurchaseId = purchase.Id;
                        catItem.LastPurchaseAt = DateTime.UtcNow;
                    }
                }
            }
        }

        await _db.SaveChangesAsync(ct);
        return await BuildPurchaseOutAsync(businessId, purchase.Id, ct);
    }

    // ─── Get ───────────────────────────────────────────────────

    public async Task<TradePurchaseOut?> GetPurchaseAsync(Guid businessId, Guid purchaseId, CancellationToken ct)
    {
        var exists = await _db.TradePurchases.AnyAsync(tp => tp.Id == purchaseId && tp.BusinessId == businessId && tp.DeletedAt == null, ct);
        if (!exists) return null;
        return await BuildPurchaseOutAsync(businessId, purchaseId, ct);
    }

    // ─── Update ────────────────────────────────────────────────

    public async Task<TradePurchaseOut> UpdatePurchaseAsync(Guid businessId, Guid purchaseId, TradePurchaseUpdateIn request, CancellationToken ct)
    {
        var purchase = await _db.TradePurchases
            .FirstOrDefaultAsync(tp => tp.Id == purchaseId && tp.BusinessId == businessId && tp.DeletedAt == null, ct)
            ?? throw new KeyNotFoundException("Purchase not found");

        if (purchase.Status == "stock_committed" || purchase.Status == "completed")
            throw new InvalidOperationException("Cannot edit a purchase that has been committed to stock.");
        if (purchase.DeletedAt != null || purchase.Status == "cancelled")
            throw new InvalidOperationException("Cannot edit a deleted or cancelled purchase.");

        if (request.PurchaseDate.HasValue) purchase.PurchaseDate = request.PurchaseDate.Value;
        if (request.SupplierId.HasValue) purchase.SupplierId = request.SupplierId.Value;
        if (request.BrokerId != null) purchase.BrokerId = request.BrokerId;
        if (request.PaymentDays.HasValue) purchase.PaymentDays = request.PaymentDays;
        if (request.Discount.HasValue) purchase.Discount = request.Discount;
        if (request.CommissionPercent.HasValue) purchase.CommissionValue = request.CommissionPercent;
        if (request.CommissionMode != null) purchase.CommissionType = request.CommissionMode;
        if (request.CommissionMoney.HasValue) purchase.CommissionMoney = request.CommissionMoney;
        if (request.FreightAmount.HasValue) purchase.FreightCharge = request.FreightAmount;
        if (request.FreightType != null) purchase.FreightType = request.FreightType;
        if (request.Status != null) purchase.Status = request.Status;

        if (request.Lines != null)
        {
            var existing = await _db.TradePurchaseLines
                .Where(l => l.TradePurchaseId == purchaseId)
                .ToListAsync(ct);
            _db.TradePurchaseLines.RemoveRange(existing);

            foreach (var line in request.Lines)
            {
                var kgPerUnit = line.KgPerUnit;
                var totalWeight = kgPerUnit.HasValue ? kgPerUnit.Value * line.Qty : (decimal?)null;
                var lineTotal = (line.LandingCost ?? 0) * line.Qty;
                var sellingTotal = line.SellingRate.HasValue ? line.SellingRate.Value * line.Qty : (decimal?)null;
                var profit = sellingTotal.HasValue ? sellingTotal - lineTotal : (decimal?)null;

                _db.TradePurchaseLines.Add(new TradePurchaseLine
                {
                    TradePurchaseId = purchaseId,
                    CatalogItemId = line.CatalogItemId,
                    ItemName = line.ItemName,
                    Qty = line.Qty,
                    Unit = line.Unit ?? "kg",
                    LandingCost = line.LandingCost ?? 0,
                    SellingRate = line.SellingRate,
                    LineTotal = lineTotal,
                    Profit = profit,
                    KgPerUnit = kgPerUnit,
                    TotalWeight = totalWeight,
                    LandingCostPerKg = totalWeight > 0 ? lineTotal / totalWeight : null,
                    DiscountPct = line.Discount,
                    TaxPercent = line.TaxPercent,
                    TaxMode = line.TaxMode,
                });
            }
        }

        await _db.SaveChangesAsync(ct);
        return await BuildPurchaseOutAsync(businessId, purchaseId, ct);
    }

    // ─── Delete ────────────────────────────────────────────────

    public async Task<bool> DeletePurchaseAsync(Guid businessId, Guid purchaseId, CancellationToken ct)
    {
        var purchase = await _db.TradePurchases
            .FirstOrDefaultAsync(tp => tp.Id == purchaseId && tp.BusinessId == businessId && tp.DeletedAt == null, ct);
        if (purchase == null) return false;
        purchase.DeletedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync(ct);
        return true;
    }

    // ─── Payment ───────────────────────────────────────────────

    public async Task<TradePurchaseOut?> UpdatePaymentAsync(Guid businessId, Guid purchaseId, PaymentUpdateIn request, CancellationToken ct)
    {
        var purchase = await _db.TradePurchases
            .FirstOrDefaultAsync(tp => tp.Id == purchaseId && tp.BusinessId == businessId && tp.DeletedAt == null, ct);
        if (purchase == null) return null;
        purchase.PaidAmount = request.PaidAmount;
        await _db.SaveChangesAsync(ct);
        return await BuildPurchaseOutAsync(businessId, purchaseId, ct);
    }

    public async Task<TradePurchaseOut?> MarkPaidAsync(Guid businessId, Guid purchaseId, MarkPaidIn request, CancellationToken ct)
    {
        var purchase = await _db.TradePurchases
            .FirstOrDefaultAsync(tp => tp.Id == purchaseId && tp.BusinessId == businessId && tp.DeletedAt == null, ct);
        if (purchase == null) return null;
        purchase.PaidAmount = request.PaidAmount ?? purchase.TotalAmount ?? 0;
        if (request.PaidAt.HasValue) purchase.DeliveryDate = DateOnly.FromDateTime(request.PaidAt.Value.DateTime);
        await _db.SaveChangesAsync(ct);
        return await BuildPurchaseOutAsync(businessId, purchaseId, ct);
    }

    public async Task<TradePurchaseOut?> CancelPurchaseAsync(Guid businessId, Guid purchaseId, CancellationToken ct)
    {
        var purchase = await _db.TradePurchases
            .FirstOrDefaultAsync(tp => tp.Id == purchaseId && tp.BusinessId == businessId && tp.DeletedAt == null, ct);
        if (purchase == null) return null;
        purchase.Status = "cancelled";
        await _db.SaveChangesAsync(ct);
        return await BuildPurchaseOutAsync(businessId, purchaseId, ct);
    }

    // ─── Delivery Pipeline ─────────────────────────────────────

    public async Task<DeliveryPipelineCountsOut> GetDeliveryPipelineAsync(Guid businessId, CancellationToken ct)
    {
        var purchases = await _db.TradePurchases
            .Where(tp => tp.BusinessId == businessId && tp.DeletedAt == null)
            .ToListAsync(ct);

        return new DeliveryPipelineCountsOut(
            Pending: purchases.Count(tp => tp.DeliveryStatus == null || tp.DeliveryStatus == "pending"),
            Dispatched: purchases.Count(tp => tp.DeliveryStatus == "dispatched"),
            InTransit: purchases.Count(tp => tp.DeliveryStatus == "in_transit"),
            Arrived: purchases.Count(tp => tp.DeliveryStatus == "arrived"),
            StaffVerifying: purchases.Count(tp => tp.DeliveryStatus == "staff_verifying"),
            StaffVerified: purchases.Count(tp => tp.DeliveryStatus == "staff_verified"),
            Partial: purchases.Count(tp => tp.DeliveryStatus == "partial"),
            StockCommitted: purchases.Count(tp => tp.DeliveryStatus == "stock_committed"),
            Cancelled: purchases.Count(tp => tp.Status == "cancelled"),
            TotalPendingAmount: purchases.Where(tp => tp.DeliveryStatus != "stock_committed" && tp.Status != "cancelled").Sum(tp => tp.TotalAmount ?? 0)
        );
    }

    // ─── Delivery Actions ──────────────────────────────────────

    public async Task<TradePurchaseOut?> PatchDeliveryAsync(Guid businessId, Guid purchaseId, DeliveryUpdateIn request, CancellationToken ct)
    {
        var purchase = await _db.TradePurchases
            .FirstOrDefaultAsync(tp => tp.Id == purchaseId && tp.BusinessId == businessId && tp.DeletedAt == null, ct);
        if (purchase == null) return null;

        if (request.DispatchNote != null) purchase.DispatchNote = request.DispatchNote;
        if (request.TruckNumber != null) purchase.VehicleNumber = request.TruckNumber;
        if (request.DriverContact != null) purchase.DeliveredBy = request.DriverContact;
        await _db.SaveChangesAsync(ct);
        return await BuildPurchaseOutAsync(businessId, purchaseId, ct);
    }

    public async Task<TradePurchaseOut?> DispatchAsync(Guid businessId, Guid purchaseId, DeliveryDispatchIn request, Guid userId, string userName, CancellationToken ct)
    {
        var purchase = await _db.TradePurchases
            .FirstOrDefaultAsync(tp => tp.Id == purchaseId && tp.BusinessId == businessId && tp.DeletedAt == null, ct);
        if (purchase == null) return null;

        purchase.DeliveryStatus = request.MarkInTransit ? "in_transit" : "dispatched";
        purchase.DispatchDate = DateOnly.FromDateTime(DateTime.UtcNow);
        purchase.DispatchNote = request.DispatchNote;
        purchase.VehicleNumber = request.TruckNumber;
        purchase.DeliveredBy = request.DriverContact;

        _db.Set<PurchaseLifecycleEvent>().Add(new PurchaseLifecycleEvent
        {
            TradePurchaseId = purchaseId,
            FromStatus = purchase.Status,
            ToStatus = "dispatched",
            ActorId = userId,
            Notes = request.DispatchNote,
            Metadata = null,
        });

        await _db.SaveChangesAsync(ct);
        return await BuildPurchaseOutAsync(businessId, purchaseId, ct);
    }

    public async Task<TradePurchaseOut?> ArriveAsync(Guid businessId, Guid purchaseId, DeliveryArriveIn request, Guid userId, string userName, CancellationToken ct)
    {
        var purchase = await _db.TradePurchases
            .FirstOrDefaultAsync(tp => tp.Id == purchaseId && tp.BusinessId == businessId && tp.DeletedAt == null, ct);
        if (purchase == null) return null;

        purchase.DeliveryStatus = "arrived";
        purchase.DeliveryDate = DateOnly.FromDateTime(DateTime.UtcNow);
        purchase.ReceivedBy = userName;
        purchase.VehicleNumber = request.TruckNumber ?? purchase.VehicleNumber;

        _db.Set<PurchaseLifecycleEvent>().Add(new PurchaseLifecycleEvent
        {
            TradePurchaseId = purchaseId,
            FromStatus = "dispatched",
            ToStatus = "arrived",
            ActorId = userId,
            Notes = request.Notes,
            Metadata = null,
        });

        await _db.SaveChangesAsync(ct);
        return await BuildPurchaseOutAsync(businessId, purchaseId, ct);
    }

    public async Task<TradePurchaseOut?> CommitStockAsync(Guid businessId, Guid purchaseId, Guid userId, string userName, CancellationToken ct)
    {
        var purchase = await _db.TradePurchases
            .FirstOrDefaultAsync(tp => tp.Id == purchaseId && tp.BusinessId == businessId && tp.DeletedAt == null, ct);
        if (purchase == null) return null;

        var lines = await _db.TradePurchaseLines
            .Where(l => l.TradePurchaseId == purchaseId)
            .ToListAsync(ct);

        foreach (var line in lines)
        {
            if (!line.CatalogItemId.HasValue) continue;
            var item = await _db.CatalogItems.FindAsync(new object[] { line.CatalogItemId.Value }, ct);
            if (item == null) continue;

            var delta = line.ReceivedQty ?? line.Qty;
            if (line.Unit != item.StockUnit && item.StockUnit != null)
            {
                delta = line.QtyInStockUnit ?? line.Qty;
            }

            item.CurrentStock += delta;
            item.LastStockUpdatedAt = DateTime.UtcNow;
            item.LastStockUpdatedBy = userName;

            _db.StockAdjustmentLogs.Add(new StockAdjustmentLog
            {
                BusinessId = businessId,
                ItemId = item.Id,
                OldQty = item.CurrentStock - delta,
                NewQty = item.CurrentStock,
                AdjustmentType = "purchase_commit",
                Reason = $"Purchase {purchase.HumanId}",
                UpdatedBy = userId,
                UpdatedAt = DateTime.UtcNow,
            });
        }

        purchase.DeliveryStatus = "stock_committed";

        _db.Set<PurchaseLifecycleEvent>().Add(new PurchaseLifecycleEvent
        {
            TradePurchaseId = purchaseId,
            FromStatus = "arrived",
            ToStatus = "stock_committed",
            ActorId = userId,
            Notes = null,
            Metadata = null,
        });

        await _db.SaveChangesAsync(ct);
        return await BuildPurchaseOutAsync(businessId, purchaseId, ct);
    }

    public async Task<TradePurchaseOut?> AutoCommitAsync(Guid businessId, Guid purchaseId, Guid userId, string userName, CancellationToken ct)
    {
        var purchase = await _db.TradePurchases
            .FirstOrDefaultAsync(tp => tp.Id == purchaseId && tp.BusinessId == businessId && tp.DeletedAt == null, ct);
        if (purchase == null) return null;

        var lines = await _db.TradePurchaseLines
            .Where(l => l.TradePurchaseId == purchaseId)
            .ToListAsync(ct);

        foreach (var line in lines)
        {
            if (!line.CatalogItemId.HasValue) continue;
            var item = await _db.CatalogItems.FindAsync(new object[] { line.CatalogItemId.Value }, ct);
            if (item == null) continue;

            var delta = line.Qty;
            item.CurrentStock += delta;
            item.LastStockUpdatedAt = DateTime.UtcNow;
            item.LastStockUpdatedBy = userName;

            _db.StockAdjustmentLogs.Add(new StockAdjustmentLog
            {
                BusinessId = businessId,
                ItemId = item.Id,
                OldQty = item.CurrentStock - delta,
                NewQty = item.CurrentStock,
                AdjustmentType = "auto_commit",
                Reason = $"Auto commit {purchase.HumanId}",
                UpdatedBy = userId,
                UpdatedAt = DateTime.UtcNow,
            });
        }

        purchase.DeliveryStatus = "stock_committed";
        purchase.ReceivedBy = userName;

        _db.Set<PurchaseLifecycleEvent>().Add(new PurchaseLifecycleEvent
        {
            TradePurchaseId = purchaseId,
            FromStatus = purchase.Status,
            ToStatus = "stock_committed",
            ActorId = userId,
            Notes = "Auto-commit",
            Metadata = null,
        });

        await _db.SaveChangesAsync(ct);
        return await BuildPurchaseOutAsync(businessId, purchaseId, ct);
    }

    public async Task<TradePurchaseOut?> VerifyDeliveryAsync(Guid businessId, Guid purchaseId, DeliveryVerifyIn request, Guid userId, string userName, CancellationToken ct)
    {
        var purchase = await _db.TradePurchases
            .FirstOrDefaultAsync(tp => tp.Id == purchaseId && tp.BusinessId == businessId && tp.DeletedAt == null, ct);
        if (purchase == null) return null;

        foreach (var vLine in request.Lines)
        {
            var line = await _db.TradePurchaseLines.FindAsync(new object[] { vLine.LineId }, ct);
            if (line == null) continue;
            line.ReceivedQty = vLine.ReceivedQty;
            line.DamagedQty = vLine.DamagedQty;
            line.ReturnQty = vLine.ReturnQty;
        }

        purchase.DeliveryStatus = "staff_verified";
        purchase.VerifiedBy = userId;
        purchase.Notes = request.Notes;

        _db.Set<PurchaseLifecycleEvent>().Add(new PurchaseLifecycleEvent
        {
            TradePurchaseId = purchaseId,
            FromStatus = "arrived",
            ToStatus = "staff_verified",
            ActorId = userId,
            Notes = request.Notes,
            Metadata = null,
        });

        await _db.SaveChangesAsync(ct);
        return await BuildPurchaseOutAsync(businessId, purchaseId, ct);
    }

    // ─── Lifecycle Events ─────────────────────────────────────

    public async Task<List<PurchaseLifecycleEventOut>> ListLifecycleEventsAsync(Guid businessId, Guid purchaseId, CancellationToken ct)
    {
        var events = await _db.Set<PurchaseLifecycleEvent>()
            .Where(e => e.TradePurchaseId == purchaseId)
            .OrderByDescending(e => e.CreatedAt)
            .ToListAsync(ct);

        var actorIds = events.Where(e => e.ActorId.HasValue).Select(e => e.ActorId!.Value).Distinct().ToHashSet();
        var actorNames = await _db.Users
            .Where(u => actorIds.Contains(u.Id))
            .ToDictionaryAsync(u => u.Id, u => u.Name ?? u.Username, ct);

        return events.Select(e => new PurchaseLifecycleEventOut(
            Id: e.Id, PurchaseId: e.TradePurchaseId, BusinessId: businessId,
            FromStatus: e.FromStatus, ToStatus: e.ToStatus,
            ActorId: e.ActorId, ActorName: e.ActorId.HasValue ? actorNames.GetValueOrDefault(e.ActorId.Value) : null,
            Notes: e.Notes, CreatedAt: e.CreatedAt
        )).ToList();
    }

    public async Task<TradePurchaseOut?> TransitionLifecycleAsync(Guid businessId, Guid purchaseId, string toStatus, Guid userId, string? notes, CancellationToken ct)
    {
        var purchase = await _db.TradePurchases
            .FirstOrDefaultAsync(tp => tp.Id == purchaseId && tp.BusinessId == businessId && tp.DeletedAt == null, ct);
        if (purchase == null) return null;

        var fromStatus = purchase.Status;
        purchase.Status = toStatus;

        _db.Set<PurchaseLifecycleEvent>().Add(new PurchaseLifecycleEvent
        {
            TradePurchaseId = purchaseId,
            FromStatus = fromStatus,
            ToStatus = toStatus,
            ActorId = userId,
            Notes = notes,
            Metadata = null,
        });

        await _db.SaveChangesAsync(ct);
        return await BuildPurchaseOutAsync(businessId, purchaseId, ct);
    }

    // ─── Helpers ───────────────────────────────────────────────

    private async Task<TradePurchaseOut> BuildPurchaseOutAsync(Guid businessId, Guid purchaseId, CancellationToken ct)
    {
        var purchase = await _db.TradePurchases
            .FirstOrDefaultAsync(tp => tp.Id == purchaseId, ct)
            ?? throw new KeyNotFoundException("Purchase not found");

        var supplier = await _db.Suppliers.FindAsync(new object[] { purchase.SupplierId }, ct);
        var broker = purchase.BrokerId.HasValue
            ? await _db.Brokers.FindAsync(new object[] { purchase.BrokerId.Value }, ct)
            : null;

        var lines = await _db.TradePurchaseLines
            .Where(l => l.TradePurchaseId == purchaseId)
            .OrderBy(l => l.SortOrder ?? 0)
            .ToListAsync(ct);

        var itemIds = lines.Where(l => l.CatalogItemId.HasValue).Select(l => l.CatalogItemId!.Value).Distinct().ToHashSet();
        var items = itemIds.Count > 0
            ? await _db.CatalogItems.Where(i => itemIds.Contains(i.Id)).ToDictionaryAsync(i => i.Id, i => i, ct)
            : new Dictionary<Guid, CatalogItem>();

        var lineOuts = lines.Select(l =>
        {
            items.TryGetValue(l.CatalogItemId ?? Guid.Empty, out var item);
            return new TradePurchaseLineOut(
                Id: l.Id, CatalogItemId: l.CatalogItemId, ItemName: l.ItemName,
                Qty: l.Qty, Unit: l.Unit, UnitType: null,
                LandingCost: l.LandingCost, SellingRate: l.SellingRate,
                LineTotal: l.LineTotal, Profit: l.Profit, TotalWeight: l.TotalWeight,
                KgPerUnit: l.KgPerUnit, LandingCostPerKg: l.LandingCostPerKg,
                Discount: l.DiscountPct, TaxPercent: l.TaxPercent, TaxMode: l.TaxMode,
                FreightType: null, FreightValue: null,
                DeliveredRate: null, BilltyRate: null,
                ItemsPerBox: item?.DefaultItemsPerBox, WeightPerTin: item?.DefaultWeightPerTin,
                PaymentDays: null, HsnCode: item?.HsnCode, ItemCode: item?.ItemCode,
                Description: null, ReceivedQty: l.ReceivedQty, DamagedQty: l.DamagedQty, ReturnQty: l.ReturnQty,
                DefaultUnit: item?.DefaultUnit, DefaultKgPerBag: item?.DefaultKgPerBag, DefaultPurchaseUnit: item?.DefaultPurchaseUnit,
                LineLandingGross: l.LineTotal ?? 0, LineSellingGross: (l.SellingRate ?? 0) * l.Qty, LineProfit: l.Profit
            );
        }).ToList();

        var totalQty = lines.Sum(l => l.Qty);
        var totalLanding = lines.Sum(l => l.LineTotal ?? 0);
        var totalSelling = lines.Sum(l => (l.SellingRate ?? 0) * l.Qty);
        var totalProfit = lines.Sum(l => l.Profit ?? 0);

        var derivedStatus = purchase.Status;
        if (purchase.DeletedAt != null) derivedStatus = "deleted";
        else if (purchase.Status == "cancelled") derivedStatus = "cancelled";
        else if (purchase.DeliveryStatus == "stock_committed") derivedStatus = "completed";
        else if (purchase.DeliveryStatus == "staff_verified") derivedStatus = "verified";
        else if (purchase.DeliveryStatus == "arrived") derivedStatus = "arrived";
        else if (purchase.DeliveryStatus == "dispatched" || purchase.DeliveryStatus == "in_transit") derivedStatus = "in_transit";

        var remaining = (purchase.TotalAmount ?? 0) - purchase.PaidAmount;

        return new TradePurchaseOut(
            Id: purchase.Id, HumanId: purchase.HumanId, BusinessId: businessId, UserId: purchase.UserId,
            InvoiceNumber: null, PurchaseDate: purchase.PurchaseDate,
            SupplierId: purchase.SupplierId ?? Guid.Empty, SupplierName: supplier?.Name ?? "Unknown",
            SupplierPhone: supplier?.Phone, SupplierGst: supplier?.GstNumber, SupplierAddress: supplier?.Address,
            BrokerId: purchase.BrokerId, BrokerName: broker?.Name, BrokerPhone: broker?.Phone,
            BrokerLocation: broker?.Location, BrokerImageUrl: broker?.ImageUrl,
            TotalAmount: purchase.TotalAmount ?? 0, PaidAmount: purchase.PaidAmount,
            Discount: purchase.Discount, CommissionPercent: purchase.CommissionValue, CommissionMode: purchase.CommissionType ?? "percent", CommissionMoney: purchase.CommissionMoney,
            DeliveredRate: null, BilltyRate: null, FreightAmount: purchase.FreightCharge, FreightType: purchase.FreightType,
            PaymentDays: purchase.PaymentDays, DueDate: null,
            Status: purchase.Status, DerivedStatus: derivedStatus, Remaining: remaining,
            IsDelivered: purchase.DeliveryStatus == "delivered" || purchase.DeliveryStatus == "stock_committed",
            DeliveryStatus: purchase.DeliveryStatus ?? "pending",
            DeliveredAt: null, DispatchedAt: purchase.DispatchDate.HasValue ? (DateTimeOffset?)purchase.DispatchDate.Value.ToDateTime(TimeOnly.MinValue) : null,
            ArrivedAt: purchase.DeliveryDate.HasValue ? (DateTimeOffset?)purchase.DeliveryDate.Value.ToDateTime(TimeOnly.MinValue) : null,
            StaffVerifiedAt: null, StaffVerifiedByName: null,
            StockCommittedAt: null, PaidAt: null,
            DispatchNote: purchase.DispatchNote, TruckNumber: purchase.VehicleNumber, DriverContact: purchase.DeliveredBy,
            DeliveryNotes: purchase.Notes, StaffVerifiedQty: null, DeliveredQtyCommitted: null,
            TotalQty: totalQty, TotalLandingSubtotal: totalLanding, TotalSellingSubtotal: totalSelling, TotalLineProfit: totalProfit,
            ItemsCount: lines.Count, HasMissingDetails: lines.Any(l => !l.CatalogItemId.HasValue),
            CreatedByName: null, CreatedAt: purchase.CreatedAt, UpdatedAt: purchase.CreatedAt,
            Lines: lineOuts, StockUpdates: null
        );
    }
}
