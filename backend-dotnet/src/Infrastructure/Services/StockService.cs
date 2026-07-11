using Microsoft.EntityFrameworkCore;
using PurchaseAssistant.Application.DTOs;
using PurchaseAssistant.Application.Interfaces;
using PurchaseAssistant.Domain.Entities.Catalog;
using PurchaseAssistant.Domain.Entities.Stock;
using PurchaseAssistant.Domain.Entities.Operations;
using PurchaseAssistant.Domain.Entities.Trade;
using PurchaseAssistant.Infrastructure.Data;
using StockPatchIn = PurchaseAssistant.Application.DTOs.Stock.StockPatchIn;

namespace PurchaseAssistant.Infrastructure.Services;

public class StockService : IStockService
{
    private readonly PurchaseAssistantDbContext _db;

    public StockService(PurchaseAssistantDbContext db)
    {
        _db = db;
    }

    public async Task<StockListOut> GetStockListAsync(
        Guid businessId,
        Guid? categoryId,
        Guid? typeId,
        bool? lowStock,
        string? q,
        int page,
        int perPage,
        string actorRole,
        CancellationToken ct)
    {
        var query = _db.CatalogItems
            .Where(i => i.BusinessId == businessId && i.DeletedAt == null)
            .Join(_db.ItemCategories,
                item => item.CategoryId,
                cat => cat.Id,
                (item, cat) => new { item, CategoryName = cat.Name })
            .GroupJoin(_db.CategoryTypes,
                x => x.item.TypeId,
                type => type.Id,
                (x, types) => new { x.item, x.CategoryName, TypeName = types.Select(t => t.Name).FirstOrDefault() });

        if (categoryId.HasValue)
            query = query.Where(x => x.item.CategoryId == categoryId.Value);

        if (typeId.HasValue)
            query = query.Where(x => x.item.TypeId == typeId.Value);

        if (lowStock == true)
            query = query.Where(x => x.item.CurrentStock <= x.item.ReorderLevel);

        if (!string.IsNullOrWhiteSpace(q))
        {
            var search = q.Trim().ToLower();
            query = query.Where(x =>
                x.item.Name.ToLower().Contains(search) ||
                (x.item.ItemCode != null && x.item.ItemCode.ToLower().Contains(search)) ||
                (x.item.Barcode != null && x.item.Barcode.ToLower().Contains(search)));
        }

        var totalCount = await query.CountAsync(ct);

        var rows = await query
            .OrderBy(x => x.item.Name)
            .Skip((page - 1) * perPage)
            .Take(perPage)
            .ToListAsync(ct);

        var items = rows.Select(r =>
        {
            var stockStatus = ComputeStockStatus(r.item.CurrentStock, r.item.ReorderLevel);
            return new StockListItemOut(
                Id: r.item.Id,
                Name: r.item.Name,
                ItemCode: r.item.ItemCode,
                Barcode: r.item.Barcode,
                CategoryName: r.CategoryName,
                TypeName: r.TypeName,
                DefaultUnit: r.item.DefaultUnit,
                CurrentStock: r.item.CurrentStock,
                ReorderLevel: r.item.ReorderLevel,
                StockUnit: r.item.StockUnit,
                DisplayUnit: r.item.DisplayUnit,
                PackageType: r.item.PackageType,
                ValidationStatus: r.item.ValidationStatus,
                LastPurchasePrice: r.item.LastPurchasePrice,
                DefaultLandingCost: r.item.DefaultLandingCost,
                DefaultSellingCost: r.item.DefaultSellingCost,
                LastSupplierId: r.item.LastSupplierId,
                LastSupplierName: null,
                LastPurchaseDate: r.item.LastPurchaseAt,
                DaysSinceLastPurchase: r.item.LastPurchaseAt.HasValue
                    ? (int?)(DateTime.UtcNow - r.item.LastPurchaseAt.Value).Days
                    : null,
                Status: stockStatus,
                PendingOrderQty: null,
                HasPendingOrder: false,
                PeriodPurchased: null,
                PeriodUsage: null,
                PhysicalCountVariance: null,
                NeedsVerification: r.item.CurrentStock < 0,
                LastMovementAt: r.item.LastStockUpdatedAt,
                StockVersion: r.item.StockVersion,
                RackLocation: r.item.RackLocation,
                LastStockUpdatedBy: r.item.LastStockUpdatedBy
            );
        }).ToList();

        return new StockListOut(items, totalCount);
    }

    public async Task<StockDetailOut> GetStockDetailAsync(Guid businessId, Guid itemId, CancellationToken ct)
    {
        var row = await _db.CatalogItems
            .Where(i => i.Id == itemId && i.BusinessId == businessId && i.DeletedAt == null)
            .Join(_db.ItemCategories,
                item => item.CategoryId,
                cat => cat.Id,
                (item, cat) => new { item, CategoryName = cat.Name })
            .GroupJoin(_db.CategoryTypes,
                x => x.item.TypeId,
                type => type.Id,
                (x, types) => new { x.item, x.CategoryName, TypeName = types.Select(t => t.Name).FirstOrDefault() })
            .FirstOrDefaultAsync(ct);

        if (row == null)
            throw new KeyNotFoundException("Catalog item not found");

        var supplierName = row.item.LastSupplierId.HasValue
            ? await _db.Suppliers
                .Where(s => s.Id == row.item.LastSupplierId.Value)
                .Select(s => s.Name)
                .FirstOrDefaultAsync(ct)
            : null;

        var brokerName = row.item.LastBrokerId.HasValue
            ? await _db.Brokers
                .Where(b => b.Id == row.item.LastBrokerId.Value)
                .Select(b => b.Name)
                .FirstOrDefaultAsync(ct)
            : null;

        return new StockDetailOut(
            Id: row.item.Id,
            Name: row.item.Name,
            ItemCode: row.item.ItemCode,
            Barcode: row.item.Barcode,
            CategoryName: row.CategoryName,
            TypeName: row.TypeName,
            DefaultUnit: row.item.DefaultUnit,
            StockUnit: row.item.StockUnit,
            DisplayUnit: row.item.DisplayUnit,
            PackageType: row.item.PackageType,
            HsnCode: row.item.HsnCode,
            CurrentStock: row.item.CurrentStock,
            ReorderLevel: row.item.ReorderLevel,
            OpeningStock: row.item.OpeningStockQty,
            OpeningStockLocked: row.item.OpeningStockLocked,
            DefaultLandingCost: row.item.DefaultLandingCost,
            DefaultSellingCost: row.item.DefaultSellingCost,
            LastPurchasePrice: row.item.LastPurchasePrice,
            LastSellingRate: row.item.LastSellingRate,
            TotalMovementIn: null,
            TotalMovementOut: null,
            LastSupplierId: row.item.LastSupplierId,
            LastSupplierName: supplierName,
            LastBrokerId: row.item.LastBrokerId,
            LastBrokerName: brokerName,
            LastPurchaseDate: row.item.LastPurchaseAt,
            LastStockUpdatedAt: row.item.LastStockUpdatedAt,
            StockVersion: row.item.StockVersion,
            ValidationStatus: row.item.ValidationStatus,
            RackLocation: row.item.RackLocation,
            PublicToken: row.item.PublicToken,
            DefaultSupplierIds: [],
            DefaultBrokerIds: []
        );
    }

    public async Task<StockDetailOut> PatchStockItemAsync(
        Guid businessId,
        Guid itemId,
        StockPatchIn request,
        Guid actorId,
        string actorName,
        string actorRole,
        CancellationToken ct)
    {
        var item = await _db.CatalogItems
            .FirstOrDefaultAsync(i => i.Id == itemId && i.BusinessId == businessId && i.DeletedAt == null, ct);

        if (item == null)
            throw new KeyNotFoundException("Catalog item not found");

        if (request.LastSeenStockVersion.HasValue)
        {
            if (item.StockVersion != request.LastSeenStockVersion.Value)
                throw new InvalidOperationException(
                    $"Stock version conflict: expected {request.LastSeenStockVersion}, current {item.StockVersion}");
        }

        var oldQty = item.CurrentStock;

        item.CurrentStock = request.NewQty;
        item.StockVersion++;
        item.LastStockUpdatedAt = DateTime.UtcNow;
        item.LastStockUpdatedBy = actorName;

        var log = new StockAdjustmentLog
        {
            BusinessId = businessId,
            ItemId = itemId,
            OldQty = oldQty,
            NewQty = request.NewQty,
            AdjustmentType = request.AdjustmentType,
            Reason = request.Reason,
            UpdatedBy = actorId,
            UpdatedAt = DateTime.UtcNow,
        };
        _db.StockAdjustmentLogs.Add(log);
        await _db.SaveChangesAsync(ct);

        return await GetStockDetailAsync(businessId, itemId, ct);
    }

    public async Task<StockShellBundleOut> GetShellBundleAsync(Guid businessId, string actorRole, CancellationToken ct)
    {
        var alerts = await GetAlertsSummaryAsync(businessId, ct);
        var deliveries = await GetDeliveryIndicatorCountsAsync(businessId, ct);
        var items = await GetStockListAsync(businessId, null, null, null, null, 1, 10, actorRole, ct);
        return new StockShellBundleOut(items.Items, deliveries, alerts, []);
    }

    public async Task<PhysicalStockCountOut> CreatePhysicalCountAsync(Guid businessId, PhysicalStockCountIn request, Guid actorId, string actorName, CancellationToken ct)
    {
        var item = await _db.CatalogItems
            .FirstOrDefaultAsync(i => i.Id == request.ItemId && i.BusinessId == businessId && i.DeletedAt == null, ct);
        if (item == null)
            throw new KeyNotFoundException("Catalog item not found");

        var log = new StockAdjustmentLog
        {
            BusinessId = businessId,
            ItemId = request.ItemId,
            OldQty = item.CurrentStock,
            NewQty = request.CountedQty,
            AdjustmentType = "physical_count",
            Reason = request.Notes ?? "Physical count",
            UpdatedBy = actorId,
            UpdatedAt = DateTime.UtcNow,
        };
        _db.StockAdjustmentLogs.Add(log);
        await _db.SaveChangesAsync(ct);

        return new PhysicalStockCountOut(
            Id: log.Id,
            ItemId: request.ItemId,
            SystemQty: item.CurrentStock,
            CountedQty: request.CountedQty,
            DifferenceQty: request.CountedQty - item.CurrentStock,
            StockUnit: request.StockUnit,
            Notes: request.Notes,
            CountedByName: actorName,
            CountedAt: DateTimeOffset.UtcNow
        );
    }

    public async Task<StockDeliveryIndicatorCountsOut> GetDeliveryIndicatorCountsAsync(Guid businessId, CancellationToken ct)
    {
        var today = DateOnly.FromDateTime(DateTime.UtcNow);
        var purchases = await _db.TradePurchases
            .Where(tp => tp.BusinessId == businessId && tp.DeletedAt == null)
            .ToListAsync(ct);
        return new StockDeliveryIndicatorCountsOut(
            Pending: purchases.Count(tp => tp.DeliveryStatus == null || tp.DeliveryStatus == "pending"),
            DeliveredToday: purchases.Count(tp => tp.DeliveryDate == today),
            DeliveredPendingScan: purchases.Count(tp => tp.DeliveryStatus == "arrived" || tp.DeliveryStatus == "staff_verified"),
            TotalDispatched: purchases.Count(tp => tp.DispatchDate.HasValue),
            TotalArrived: purchases.Count(tp => tp.DeliveryDate.HasValue)
        );
    }

    public async Task<StockListCompactOut> GetCompactListAsync(Guid businessId, CancellationToken ct)
    {
        var items = await _db.CatalogItems
            .Where(i => i.BusinessId == businessId && i.DeletedAt == null)
            .OrderBy(i => i.Name)
            .Select(i => new StockListItemMinimalOut(i.Id, i.Name, i.ItemCode, i.Barcode, i.CurrentStock))
            .ToListAsync(ct);
        return new StockListCompactOut(items);
    }

    public async Task<List<StockSearchHit>> SearchStockAsync(Guid businessId, string q, int limit, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(q)) return [];
        var search = q.Trim().ToLower();
        return await _db.CatalogItems
            .Where(i => i.BusinessId == businessId && i.DeletedAt == null
                && (i.Name.ToLower().Contains(search)
                    || (i.ItemCode != null && i.ItemCode.ToLower().Contains(search))
                    || (i.Barcode != null && i.Barcode.ToLower().Contains(search))))
            .Join(_db.ItemCategories, i => i.CategoryId, c => c.Id, (i, c) => new { i, CategoryName = c.Name })
            .Take(limit)
            .Select(x => new StockSearchHit(x.i.Id, x.i.Name, x.i.ItemCode, x.i.Barcode, x.i.CurrentStock, x.CategoryName))
            .ToListAsync(ct);
    }

    public async Task<StockAlertsSummaryOut> GetAlertsSummaryAsync(Guid businessId, CancellationToken ct)
    {
        var items = await _db.CatalogItems
            .Where(i => i.BusinessId == businessId && i.DeletedAt == null)
            .ToListAsync(ct);
        return new StockAlertsSummaryOut(
            LowStock: items.Count(i => i.CurrentStock > 0 && i.CurrentStock <= i.ReorderLevel),
            Critical: items.Count(i => i.CurrentStock < 0),
            OutOfStock: items.Count(i => i.CurrentStock == 0),
            Overstock: 0,
            PendingVerification: items.Count(i => i.ValidationStatus == "pending"),
            Disputed: 0
        );
    }

    public async Task<WarehouseAlertsSummaryOut> GetWarehouseAlertsSummaryAsync(Guid businessId, CancellationToken ct)
    {
        var items = await _db.CatalogItems
            .Where(i => i.BusinessId == businessId && i.DeletedAt == null)
            .ToListAsync(ct);
        var pendingDelivery = await _db.TradePurchases
            .CountAsync(tp => tp.BusinessId == businessId && tp.DeletedAt == null
                && (tp.DeliveryStatus == null || tp.DeliveryStatus == "pending"), ct);
        return new WarehouseAlertsSummaryOut(
            TotalAlerts: items.Count(i => i.CurrentStock <= i.ReorderLevel || i.CurrentStock < 0),
            LowStock: items.Count(i => i.CurrentStock > 0 && i.CurrentStock <= i.ReorderLevel),
            OutOfStock: items.Count(i => i.CurrentStock == 0),
            PendingDelivery: pendingDelivery,
            PendingVerification: items.Count(i => i.ValidationStatus == "pending"),
            Disputed: 0,
            RecentAudit: 0
        );
    }

    public async Task<LowStockOpsOut> GetLowStockOperationsAsync(Guid businessId, int page, int perPage, CancellationToken ct)
    {
        var items = await _db.CatalogItems
            .Where(i => i.BusinessId == businessId && i.DeletedAt == null && i.CurrentStock <= i.ReorderLevel)
            .OrderBy(i => i.CurrentStock)
            .Skip((page - 1) * perPage)
            .Take(perPage)
            .ToListAsync(ct);

        var itemIds = items.Select(i => i.Id).ToHashSet();
        var lastPurchases = await _db.TradePurchaseLines
            .Where(l => l.CatalogItemId.HasValue && itemIds.Contains(l.CatalogItemId.Value))
            .Join(_db.TradePurchases.Where(tp => tp.BusinessId == businessId),
                l => l.TradePurchaseId, tp => tp.Id, (l, tp) => new { l, tp })
            .GroupBy(x => x.l.CatalogItemId!.Value)
            .Select(g => new { ItemId = g.Key, LastDate = g.Max(x => (DateTime?)x.tp.PurchaseDate.ToDateTime(TimeOnly.MinValue)), LastSupplierId = g.OrderByDescending(x => x.tp.PurchaseDate).Select(x => (Guid?)x.tp.SupplierId).FirstOrDefault() })
            .ToDictionaryAsync(x => x.ItemId, ct);

        var supplierIds = lastPurchases.Values.Where(x => x.LastSupplierId.HasValue).Select(x => x.LastSupplierId!.Value).Distinct().ToHashSet();
        var sNames = await _db.Suppliers.Where(s => supplierIds.Contains(s.Id)).ToDictionaryAsync(s => s.Id, s => s.Name, ct);

        var opsItems = items.Select(i =>
        {
            var lp = lastPurchases.GetValueOrDefault(i.Id);
            var shortage = i.ReorderLevel - i.CurrentStock;
            var priority = shortage > 0 ? (double)shortage * 10 : 0;
            var band = shortage > 50 ? "high" : shortage > 20 ? "medium" : "low";
            return new LowStockOpsItemOut(
                Id: i.Id, Name: i.Name, ItemCode: i.ItemCode, Barcode: i.Barcode,
                CategoryName: null, DefaultUnit: i.DefaultUnit,
                CurrentStock: i.CurrentStock, ReorderLevel: i.ReorderLevel,
                Shortage: shortage, PriorityScore: priority, Band: band,
                OutOfStock: i.CurrentStock == 0, Delayed: lp?.LastDate != null && (DateTime.UtcNow - lp.LastDate.Value).Days > 30,
                Mismatch: false, NeedsVerification: i.CurrentStock < 0,
                LifecycleStage: i.CurrentStock <= 0 ? "out_of_stock" : "low",
                LastPurchasePrice: i.LastPurchasePrice,
                LastSupplierId: lp?.LastSupplierId, LastSupplierName: lp?.LastSupplierId.HasValue == true ? sNames.GetValueOrDefault(lp.LastSupplierId.Value) : null,
                LastPurchaseDate: lp?.LastDate, LastMovementAt: i.LastStockUpdatedAt
            );
        }).ToList();

        var summary = new LowStockOpsSummaryOut(
            ShortageItems: opsItems.Count(x => x.Shortage > 0),
            OutOfStockItems: opsItems.Count(x => x.OutOfStock),
            DelayedItems: opsItems.Count(x => x.Delayed),
            MismatchItems: opsItems.Count(x => x.Mismatch),
            VerificationNeeded: opsItems.Count(x => x.NeedsVerification)
        );

        return new LowStockOpsOut(summary, opsItems, opsItems.Count);
    }

    public async Task<StockIntelligenceOut> GetStockIntelligenceAsync(Guid businessId, Guid itemId, CancellationToken ct)
    {
        var item = await _db.CatalogItems
            .FirstOrDefaultAsync(i => i.Id == itemId && i.BusinessId == businessId && i.DeletedAt == null, ct);
        if (item == null) throw new KeyNotFoundException("Item not found");

        var lastLines = await _db.TradePurchaseLines
            .Where(l => l.CatalogItemId == itemId)
            .Join(_db.TradePurchases.Where(tp => tp.BusinessId == businessId && tp.DeletedAt == null),
                l => l.TradePurchaseId, tp => tp.Id, (l, tp) => new { l, tp.PurchaseDate })
            .OrderByDescending(x => x.PurchaseDate)
            .Take(10)
            .ToListAsync(ct);

        var avgLanding = lastLines.Any() ? lastLines.Average(x => (double)x.l.LandingCost) : 0;
        var avgSelling = lastLines.Any() && lastLines.Any(x => x.l.SellingRate.HasValue)
            ? lastLines.Where(x => x.l.SellingRate.HasValue).Average(x => (double)x.l.SellingRate!.Value)
            : 0;
        var daysSince = item.LastPurchaseAt.HasValue ? (int)(DateTime.UtcNow - item.LastPurchaseAt.Value).Days : -1;

        string? supplierName = null;
        if (item.LastSupplierId.HasValue)
            supplierName = await _db.Suppliers.Where(s => s.Id == item.LastSupplierId.Value).Select(s => s.Name).FirstOrDefaultAsync(ct);

        return new StockIntelligenceOut(
            SuggestedQty: item.ReorderLevel > 0 ? Math.Max(0, item.ReorderLevel - item.CurrentStock) : null,
            AvgIntervalDays: lastLines.Count > 1 ? (int?)null : null,
            DefaultSupplierId: item.LastSupplierId, DefaultSupplierName: supplierName,
            AvgLandingCost: (decimal?)avgLanding, AvgSellingRate: (decimal?)avgSelling,
            PeriodUsage: null, PeriodPurchased: lastLines.Sum(x => (decimal?)x.l.Qty),
            DaysSinceLastPurchase: daysSince
        );
    }

    public async Task<StockItemActivityOut> GetStockActivityAsync(Guid businessId, Guid itemId, int limit, CancellationToken ct)
    {
        var logs = await _db.StockAdjustmentLogs
            .Where(l => l.ItemId == itemId && l.BusinessId == businessId)
            .OrderByDescending(l => l.UpdatedAt)
            .Take(limit)
            .ToListAsync(ct);

        var userIds = logs.Where(l => l.UpdatedBy.HasValue).Select(l => l.UpdatedBy!.Value).Distinct().ToHashSet();
        var userNames = await _db.Users.Where(u => userIds.Contains(u.Id)).ToDictionaryAsync(u => u.Id, u => u.Name ?? u.Username, ct);

        var events = logs.Select(l =>
        {
            var delta = (l.NewQty ?? 0) - (l.OldQty ?? 0);
            return new StockActivityEventOut(
                Id: l.Id, Kind: l.AdjustmentType ?? "adjustment", DeltaQty: delta,
                QtyBefore: l.OldQty, QtyAfter: l.NewQty,
                Unit: null, Reason: l.Reason,
                ActorName: l.UpdatedBy.HasValue ? userNames.GetValueOrDefault(l.UpdatedBy.Value) : null,
                CreatedAt: l.UpdatedAt.HasValue ? (DateTimeOffset?)l.UpdatedAt.Value : null
            );
        }).ToList();

        return new StockItemActivityOut(itemId, events);
    }

    public async Task<StockMovementOut> CreateAdjustmentAsync(Guid businessId, CreateStockAdjustmentRequest request, Guid actorId, string actorName, CancellationToken ct)
    {
        var item = await _db.CatalogItems
            .FirstOrDefaultAsync(i => i.Id == request.CatalogItemId && i.BusinessId == businessId && i.DeletedAt == null, ct)
            ?? throw new KeyNotFoundException("Item not found");

        var oldQty = item.CurrentStock;
        item.CurrentStock += request.Qty;
        item.StockVersion++;
        item.LastStockUpdatedAt = DateTime.UtcNow;
        item.LastStockUpdatedBy = actorName;

        var log = new StockAdjustmentLog
        {
            BusinessId = businessId, ItemId = item.Id,
            OldQty = oldQty, NewQty = item.CurrentStock,
            AdjustmentType = request.AdjustmentType,
            Reason = request.Reason, UpdatedBy = actorId, UpdatedAt = DateTime.UtcNow,
        };
        _db.StockAdjustmentLogs.Add(log);
        await _db.SaveChangesAsync(ct);

        return new StockMovementOut(log.Id, item.Id, request.AdjustmentType, request.Qty, oldQty, item.CurrentStock, request.Unit, request.Reason, null, "adjustment", null, actorName, DateTimeOffset.UtcNow);
    }

    public async Task<StockMovementOut> CreateMovementAsync(Guid businessId, StockMovementCreateIn request, Guid actorId, string actorName, CancellationToken ct)
    {
        var item = await _db.CatalogItems
            .FirstOrDefaultAsync(i => i.Id == request.ItemId && i.BusinessId == businessId && i.DeletedAt == null, ct)
            ?? throw new KeyNotFoundException("Item not found");

        var oldQty = item.CurrentStock;
        item.CurrentStock += request.Qty;
        item.StockVersion++;
        item.LastStockUpdatedAt = DateTime.UtcNow;

        var movement = new StockMovement
        {
            BusinessId = businessId, ItemId = item.Id,
            FromLocation = request.FromLocation, ToLocation = request.ToLocation,
            Qty = request.Qty, Unit = request.Unit, Notes = request.Notes,
            MovedBy = actorId,
        };
        _db.StockMovements.Add(movement);

        var log = new StockAdjustmentLog
        {
            BusinessId = businessId, ItemId = item.Id,
            OldQty = oldQty, NewQty = item.CurrentStock,
            AdjustmentType = "movement", Reason = request.Notes,
            UpdatedBy = actorId, UpdatedAt = DateTime.UtcNow,
        };
        _db.StockAdjustmentLogs.Add(log);
        await _db.SaveChangesAsync(ct);

        return new StockMovementOut(movement.Id, item.Id, "movement", request.Qty, oldQty, item.CurrentStock, request.Unit, request.Notes, null, "movement", null, actorName, DateTimeOffset.UtcNow);
    }

    public async Task<StockPhysicalUpdateOut> PhysicalUpdateAsync(Guid businessId, Guid itemId, StockPhysicalUpdateIn request, Guid actorId, string actorName, CancellationToken ct)
    {
        var item = await _db.CatalogItems
            .FirstOrDefaultAsync(i => i.Id == itemId && i.BusinessId == businessId && i.DeletedAt == null, ct)
            ?? throw new KeyNotFoundException("Item not found");

        var oldStock = item.CurrentStock;
        item.CurrentStock = request.CountedQty;
        item.StockVersion = request.ExpectedVersion + 1;
        item.LastStockUpdatedAt = DateTime.UtcNow;
        item.LastStockUpdatedBy = actorName;

        _db.StockAdjustmentLogs.Add(new StockAdjustmentLog
        {
            BusinessId = businessId, ItemId = itemId,
            OldQty = oldStock, NewQty = request.CountedQty,
            AdjustmentType = "physical_update", Reason = request.Reason,
            UpdatedBy = actorId, UpdatedAt = DateTime.UtcNow,
        });
        await _db.SaveChangesAsync(ct);

        return new StockPhysicalUpdateOut(itemId, oldStock, request.CountedQty, request.CountedQty - oldStock, item.StockVersion);
    }

    public async Task<StockVerifyCountOut> VerifyCountAsync(Guid businessId, Guid itemId, StockVerifyCountIn request, Guid actorId, string actorName, CancellationToken ct)
    {
        var item = await _db.CatalogItems
            .FirstOrDefaultAsync(i => i.Id == itemId && i.BusinessId == businessId && i.DeletedAt == null, ct)
            ?? throw new KeyNotFoundException("Item not found");

        var diff = request.CountedQty - item.CurrentStock;
        var match = Math.Abs(diff) < 0.01m;
        return new StockVerifyCountOut(itemId, item.CurrentStock, request.CountedQty, diff, match);
    }

    public async Task<StockMovementOut?> UndoLastAsync(Guid businessId, Guid itemId, Guid actorId, string actorName, CancellationToken ct)
    {
        var lastLog = await _db.StockAdjustmentLogs
            .Where(l => l.ItemId == itemId && l.BusinessId == businessId)
            .OrderByDescending(l => l.UpdatedAt)
            .FirstOrDefaultAsync(ct);
        if (lastLog == null) return null;

        var item = await _db.CatalogItems.FindAsync(new object[] { itemId }, ct);
        if (item == null) return null;

        var oldQty = item.CurrentStock;
        item.CurrentStock = lastLog.OldQty ?? 0;
        item.StockVersion++;
        item.LastStockUpdatedAt = DateTime.UtcNow;

        var undoLog = new StockAdjustmentLog
        {
            BusinessId = businessId, ItemId = itemId,
            OldQty = oldQty, NewQty = item.CurrentStock,
            AdjustmentType = "undo", Reason = $"Undo: {lastLog.AdjustmentType}",
            UpdatedBy = actorId, UpdatedAt = DateTime.UtcNow,
        };
        _db.StockAdjustmentLogs.Add(undoLog);
        await _db.SaveChangesAsync(ct);

        return new StockMovementOut(undoLog.Id, itemId, "undo", item.CurrentStock - oldQty, oldQty, item.CurrentStock, null, undoLog.Reason, null, "undo", null, actorName, DateTimeOffset.UtcNow);
    }

    public async Task NotifyOwnerAsync(Guid businessId, Guid itemId, NotifyOwnerIn request, Guid actorId, CancellationToken ct)
    {
        var item = await _db.CatalogItems.FindAsync(new object[] { itemId }, ct);
        var ownerMembers = await _db.Memberships
            .Where(m => m.BusinessId == businessId && m.Role == "owner")
            .Select(m => m.UserId)
            .ToListAsync(ct);

        foreach (var uid in ownerMembers)
        {
            _db.Set<Domain.Entities.Notifications.Notification>().Add(new Domain.Entities.Notifications.Notification
            {
                UserId = uid,
                BusinessId = businessId,
                Title = $"Stock Alert: {item?.Name ?? "Unknown"}",
                Body = request.Message ?? $"Stock notification for {item?.Name}",
                Kind = "stock_alert",
            });
        }
        await _db.SaveChangesAsync(ct);
    }

    public async Task<QuickPurchaseOut> CreateQuickPurchaseAsync(Guid businessId, Guid itemId, QuickPurchaseIn request, Guid actorId, CancellationToken ct)
    {
        var item = await _db.CatalogItems
            .FirstOrDefaultAsync(i => i.Id == itemId && i.BusinessId == businessId && i.DeletedAt == null, ct)
            ?? throw new KeyNotFoundException("Item not found");

        var total = request.Qty * (request.Rate ?? 0);
        var hp = await _db.TradePurchases.CountAsync(tp => tp.BusinessId == businessId, ct);
        var humanId = $"QP-{DateTime.UtcNow:yyMMdd}-{hp + 1}";

        var purchase = new TradePurchase
        {
            BusinessId = businessId, UserId = actorId, HumanId = humanId,
            PurchaseDate = DateOnly.FromDateTime(DateTime.UtcNow),
            SupplierId = request.SupplierId, Status = "quick",
            TotalAmount = total, PaidAmount = 0,
        };
        _db.TradePurchases.Add(purchase);
        await _db.SaveChangesAsync(ct);

        var rate = request.Rate ?? item.LastPurchasePrice ?? 0;
        _db.TradePurchaseLines.Add(new TradePurchaseLine
        {
            TradePurchaseId = purchase.Id, CatalogItemId = itemId,
            ItemName = item.Name, Qty = request.Qty, Unit = request.Unit ?? item.DefaultUnit ?? "kg",
            LandingCost = rate, LineTotal = total,
        });

        var oldQty = item.CurrentStock;
        item.CurrentStock += request.Qty;
        item.LastStockUpdatedAt = DateTime.UtcNow;
        item.LastPurchasePrice = rate;
        item.LastTradePurchaseId = purchase.Id;

        _db.StockAdjustmentLogs.Add(new StockAdjustmentLog
        {
            BusinessId = businessId, ItemId = itemId,
            OldQty = oldQty, NewQty = item.CurrentStock,
            AdjustmentType = "quick_purchase", Reason = $"Quick purchase {purchase.HumanId}",
            UpdatedBy = actorId, UpdatedAt = DateTime.UtcNow,
        });
        await _db.SaveChangesAsync(ct);

        return new QuickPurchaseOut(purchase.Id, itemId, request.Qty, rate, total, "quick");
    }

    public async Task<OpeningStockSetupOut> GetOpeningStockSetupAsync(Guid businessId, string? status, string? q, int page, int perPage, CancellationToken ct)
    {
        var query = _db.CatalogItems.Where(i => i.BusinessId == businessId && i.DeletedAt == null);

        if (status == "missing") query = query.Where(i => i.OpeningStockQty == null || !i.OpeningStockLocked);
        if (status == "set") query = query.Where(i => i.OpeningStockQty != null && i.OpeningStockLocked);
        if (!string.IsNullOrWhiteSpace(q))
        {
            var s = q.Trim().ToLower();
            query = query.Where(i => i.Name.ToLower().Contains(s));
        }

        var total = await query.CountAsync(ct);
        var items = await query.OrderBy(i => i.Name).Skip((page - 1) * perPage).Take(perPage)
            .Select(i => new OpeningStockSetupItemOut(
                i.Id, i.Name, i.DefaultUnit, i.OpeningStockQty, i.OpeningStockLocked,
                i.OpeningStockQty.HasValue ? "set" : "missing"
            )).ToListAsync(ct);

        return new OpeningStockSetupOut(items, total);
    }

    public async Task<OpeningStockMissingOut> GetOpeningStockMissingAsync(Guid businessId, CancellationToken ct)
    {
        var items = await _db.CatalogItems
            .Where(i => i.BusinessId == businessId && i.DeletedAt == null && (i.OpeningStockQty == null || !i.OpeningStockLocked))
            .OrderBy(i => i.Name)
            .Select(i => new OpeningStockSetupItemOut(i.Id, i.Name, i.DefaultUnit, i.OpeningStockQty, i.OpeningStockLocked, "missing"))
            .ToListAsync(ct);
        return new OpeningStockMissingOut(items, items.Count);
    }

    public async Task<StockMovementOut> SetOpeningStockAsync(Guid businessId, Guid itemId, OpeningStockIn request, Guid actorId, string actorName, CancellationToken ct)
    {
        var item = await _db.CatalogItems
            .FirstOrDefaultAsync(i => i.Id == itemId && i.BusinessId == businessId && i.DeletedAt == null, ct)
            ?? throw new KeyNotFoundException("Item not found");

        var oldQty = item.CurrentStock;
        item.OpeningStockQty = request.Qty;
        item.OpeningStockLocked = true;
        item.OpeningStockSetAt = DateTime.UtcNow;
        item.OpeningStockSetBy = actorName;
        item.CurrentStock = request.Qty;
        item.LastStockUpdatedAt = DateTime.UtcNow;

        var log = new StockAdjustmentLog
        {
            BusinessId = businessId, ItemId = itemId,
            OldQty = oldQty, NewQty = request.Qty,
            AdjustmentType = "opening_stock", Reason = request.Reason ?? "Opening stock setup",
            UpdatedBy = actorId, UpdatedAt = DateTime.UtcNow,
        };
        _db.StockAdjustmentLogs.Add(log);
        await _db.SaveChangesAsync(ct);

        return new StockMovementOut(log.Id, itemId, "opening_stock", request.Qty - oldQty, oldQty, request.Qty, null, request.Reason, null, "opening", null, actorName, DateTimeOffset.UtcNow);
    }

    public async Task<InventorySummaryOut> GetInventorySummaryAsync(Guid businessId, CancellationToken ct)
    {
        var items = await _db.CatalogItems
            .Where(i => i.BusinessId == businessId && i.DeletedAt == null)
            .Join(_db.ItemCategories, i => i.CategoryId, c => c.Id, (i, c) => new { i, c.Name })
            .ToListAsync(ct);

        var byCat = items.GroupBy(x => x.Name).Select(g =>
        {
            var totalStock = g.Sum(x => x.i.CurrentStock);
            var totalValue = g.Sum(x => x.i.CurrentStock * (x.i.DefaultLandingCost ?? 0));
            return new InventorySummaryItemOut(g.Key, g.Count(), totalStock, totalValue);
        }).ToList();

        return new InventorySummaryOut(byCat, items.Sum(i => i.i.CurrentStock), items.Sum(i => i.i.CurrentStock * (i.i.DefaultLandingCost ?? 0)));
    }

    public async Task<StockTotalsOut> GetStockTotalsAsync(Guid businessId, CancellationToken ct)
    {
        var items = await _db.CatalogItems
            .Where(i => i.BusinessId == businessId && i.DeletedAt == null)
            .ToListAsync(ct);

        var byUnit = items.GroupBy(i => i.DefaultUnit ?? "unit").Select(g => new StockTotalsItemOut(g.Key, g.Sum(i => i.CurrentStock), g.Count())).ToList();
        return new StockTotalsOut(byUnit);
    }

    public async Task<ReorderListOut> GetReorderListAsync(Guid businessId, CancellationToken ct)
    {
        var entries = await _db.ReorderLists
            .Where(r => r.BusinessId == businessId)
            .Join(_db.CatalogItems, r => r.CatalogItemId, i => i.Id, (r, i) => new { r, i })
            .OrderBy(x => x.i.CurrentStock)
            .ToListAsync(ct);

        return new ReorderListOut(entries.Select(x =>
        {
            var status = x.i.CurrentStock <= 0 ? "out_of_stock" : x.i.CurrentStock <= x.i.ReorderLevel ? "low" : "ok";
            return new ReorderListEntryOut(x.r.Id, x.i.Id, x.i.Name, x.i.ItemCode, x.i.DefaultUnit,
                x.i.CurrentStock, x.i.ReorderLevel, null, x.i.LastPurchasePrice,
                x.i.LastPurchaseAt, status, x.r.CreatedAt);
        }).ToList());
    }

    public async Task PatchReorderEntryAsync(Guid businessId, Guid entryId, ReorderListPatchIn request, CancellationToken ct)
    {
        var entry = await _db.ReorderLists.FirstOrDefaultAsync(r => r.Id == entryId && r.BusinessId == businessId, ct);
        if (entry != null)
        {
            if (request.Notes != null) entry.Notes = request.Notes;
            await _db.SaveChangesAsync(ct);
        }
    }

    public async Task DeleteReorderEntryAsync(Guid businessId, Guid entryId, CancellationToken ct)
    {
        var entry = await _db.ReorderLists.FirstOrDefaultAsync(r => r.Id == entryId && r.BusinessId == businessId, ct);
        if (entry != null)
        {
            _db.ReorderLists.Remove(entry);
            await _db.SaveChangesAsync(ct);
        }
    }

    public async Task<ReorderListEntryOut> AddToReorderListAsync(Guid businessId, Guid itemId, Guid actorId, CancellationToken ct)
    {
        var existing = await _db.ReorderLists.FirstOrDefaultAsync(r => r.BusinessId == businessId && r.CatalogItemId == itemId, ct);
        if (existing != null)
            return await GetReorderListAsync(businessId, ct).ContinueWith(t => t.Result.Items.First(i => i.ItemId == itemId), ct);

        var item = await _db.CatalogItems.FindAsync(new object[] { itemId }, ct)
            ?? throw new KeyNotFoundException("Item not found");

        var entry = new ReorderList { BusinessId = businessId, CatalogItemId = itemId, Notes = null };
        _db.ReorderLists.Add(entry);
        await _db.SaveChangesAsync(ct);

        return new ReorderListEntryOut(entry.Id, itemId, item.Name, item.ItemCode, item.DefaultUnit,
            item.CurrentStock, item.ReorderLevel, null, item.LastPurchasePrice,
            item.LastPurchaseAt, "low", entry.CreatedAt);
    }

    public async Task<BarcodeLookupOut?> BarcodeLookupAsync(Guid businessId, string barcode, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(barcode)) return null;
        var item = await _db.CatalogItems
            .Where(i => i.BusinessId == businessId && i.Barcode == barcode && i.DeletedAt == null)
            .Select(i => new { i, CatName = _db.ItemCategories.Where(c => c.Id == i.CategoryId).Select(c => c.Name).FirstOrDefault() })
            .FirstOrDefaultAsync(ct);
        if (item == null) return null;
        return new BarcodeLookupOut(item.i.Id, item.i.Name, item.i.ItemCode, item.i.Barcode,
            item.i.CurrentStock, item.i.DefaultUnit, item.i.CategoryId, item.CatName,
            item.i.TypeId, null, item.i.DefaultLandingCost, item.i.DefaultSellingCost);
    }

    public async Task<BarcodeLabelOut> GetBarcodeLabelAsync(Guid businessId, Guid itemId, CancellationToken ct)
    {
        var item = await _db.CatalogItems
            .FirstOrDefaultAsync(i => i.Id == itemId && i.BusinessId == businessId && i.DeletedAt == null, ct)
            ?? throw new KeyNotFoundException("Item not found");
        return new BarcodeLabelOut(item.Id, item.Name, item.Barcode, item.ItemCode, item.DefaultLandingCost, item.DefaultSellingCost);
    }

    public async Task<BarcodeBatchOut> BatchBarcodeLabelsAsync(Guid businessId, BarcodeBatchIn request, CancellationToken ct)
    {
        var items = await _db.CatalogItems
            .Where(i => request.ItemIds.Contains(i.Id) && i.BusinessId == businessId && i.DeletedAt == null)
            .Select(i => new BarcodeLabelOut(i.Id, i.Name, i.Barcode, i.ItemCode, i.DefaultLandingCost, i.DefaultSellingCost))
            .ToListAsync(ct);
        return new BarcodeBatchOut(items);
    }

    public async Task<List<StockAuditFeedItemOut>> GetAuditFeedAsync(Guid businessId, int limit, CancellationToken ct)
    {
        var logs = await _db.StockAdjustmentLogs
            .Where(l => l.BusinessId == businessId)
            .OrderByDescending(l => l.UpdatedAt)
            .Take(limit)
            .ToListAsync(ct);

        var itemIds = logs.Select(l => l.ItemId).Distinct().ToHashSet();
        var names = await _db.CatalogItems.Where(i => itemIds.Contains(i.Id)).ToDictionaryAsync(i => i.Id, i => i.Name, ct);
        var userIds = logs.Where(l => l.UpdatedBy.HasValue).Select(l => l.UpdatedBy!.Value).Distinct().ToHashSet();
        var userNames = await _db.Users.Where(u => userIds.Contains(u.Id)).ToDictionaryAsync(u => u.Id, u => u.Name ?? u.Username, ct);

        return logs.Select(l => new StockAuditFeedItemOut(
            l.Id, l.ItemId, names.GetValueOrDefault(l.ItemId, "Unknown"),
            l.AdjustmentType ?? "adjustment", l.OldQty ?? 0, l.NewQty ?? 0,
            l.Reason, l.UpdatedBy.HasValue ? userNames.GetValueOrDefault(l.UpdatedBy.Value) : null,
            l.UpdatedAt.HasValue ? (DateTimeOffset)l.UpdatedAt.Value : DateTimeOffset.UtcNow
        )).ToList();
    }

    public Task<List<StockAdjustmentOut>> GetRecentAdjustmentsAsync(Guid businessId, int limit, CancellationToken ct)
        => GetItemAuditAsync(businessId, Guid.Empty, limit, ct);

    public async Task<List<StockVarianceOut>> GetTodayVariancesAsync(Guid businessId, CancellationToken ct)
    {
        var today = DateTime.UtcNow.Date;
        var counts = await _db.StockPhysicalCounts
            .Where(p => p.BusinessId == businessId && p.CreatedAt >= today)
            .ToListAsync(ct);

        var itemIds = counts.Select(p => p.ItemId).Distinct().ToHashSet();
        var names = await _db.CatalogItems.Where(i => itemIds.Contains(i.Id)).ToDictionaryAsync(i => i.Id, i => i.Name, ct);
        var items = await _db.CatalogItems.Where(i => itemIds.Contains(i.Id)).ToDictionaryAsync(i => i.Id, i => i.CurrentStock, ct);

        return counts.Select(p =>
        {
            var variance = (p.Variance ?? 0);
            return new StockVarianceOut(p.ItemId, names.GetValueOrDefault(p.ItemId, "Unknown"),
                items.GetValueOrDefault(p.ItemId), p.CountedQty, null, variance, Math.Abs(variance) > 5);
        }).ToList();
    }

    public async Task<List<StockAdjustmentOut>> GetItemAuditAsync(Guid businessId, Guid itemId, int limit, CancellationToken ct)
    {
        var query = _db.StockAdjustmentLogs.Where(l => l.BusinessId == businessId);
        if (itemId != Guid.Empty) query = query.Where(l => l.ItemId == itemId);

        var logs = await query.OrderByDescending(l => l.UpdatedAt).Take(limit).ToListAsync(ct);
        var itemIds = logs.Select(l => l.ItemId).Distinct().ToHashSet();
        var names = await _db.CatalogItems.Where(i => itemIds.Contains(i.Id)).ToDictionaryAsync(i => i.Id, i => i.Name, ct);
        var userIds = logs.Where(l => l.UpdatedBy.HasValue).Select(l => l.UpdatedBy!.Value).Distinct().ToHashSet();
        var userNames = await _db.Users.Where(u => userIds.Contains(u.Id)).ToDictionaryAsync(u => u.Id, u => u.Name ?? u.Username, ct);

        return logs.Select(l => new StockAdjustmentOut(
            l.Id, l.ItemId, names.GetValueOrDefault(l.ItemId, "Unknown"),
            l.OldQty ?? 0, l.NewQty ?? 0, l.AdjustmentType ?? "adjustment", l.Reason,
            l.UpdatedBy, l.UpdatedBy.HasValue ? userNames.GetValueOrDefault(l.UpdatedBy.Value) : null,
            l.UpdatedAt.HasValue ? (DateTimeOffset)l.UpdatedAt.Value : DateTimeOffset.UtcNow
        )).ToList();
    }

    public async Task<List<StockMovementOut>> GetMovementsAsync(Guid businessId, Guid? itemId, int limit, CancellationToken ct)
    {
        var query = _db.StockMovements.Where(m => m.BusinessId == businessId);
        if (itemId.HasValue) query = query.Where(m => m.ItemId == itemId.Value);

        var movements = await query.OrderByDescending(m => m.CreatedAt).Take(limit).ToListAsync(ct);
        var userIds = movements.Where(m => m.MovedBy.HasValue).Select(m => m.MovedBy!.Value).Distinct().ToHashSet();
        var userNames = await _db.Users.Where(u => userIds.Contains(u.Id)).ToDictionaryAsync(u => u.Id, u => u.Name ?? u.Username, ct);

        return movements.Select(m => new StockMovementOut(
            m.Id, m.ItemId, "movement", m.Qty ?? 0, null, null, m.Unit, m.Notes, null,
            "movement", null, m.MovedBy.HasValue ? userNames.GetValueOrDefault(m.MovedBy.Value) : null,
            m.CreatedAt
        )).ToList();
    }

    public async Task<List<PhysicalStockCountOut>> GetPhysicalCountsAsync(Guid businessId, Guid? itemId, int limit, CancellationToken ct)
    {
        var query = _db.StockPhysicalCounts.Where(p => p.BusinessId == businessId);
        if (itemId.HasValue) query = query.Where(p => p.ItemId == itemId.Value);

        var counts = await query.OrderByDescending(p => p.CreatedAt).Take(limit).ToListAsync(ct);
        var userIds = counts.Where(p => p.CountedBy.HasValue).Select(p => p.CountedBy!.Value).Distinct().ToHashSet();
        var userNames = await _db.Users.Where(u => userIds.Contains(u.Id)).ToDictionaryAsync(u => u.Id, u => u.Name ?? u.Username, ct);

        return counts.Select(p => new PhysicalStockCountOut(
            p.Id, p.ItemId, p.SystemQty ?? 0, p.CountedQty ?? 0, p.Variance ?? 0,
            p.Unit, p.Notes, p.CountedBy.HasValue ? userNames.GetValueOrDefault(p.CountedBy.Value) : null, p.CreatedAt
        )).ToList();
    }

    public async Task<List<StaffPurchaseLogOut>> GetStaffPurchasesAsync(Guid businessId, int limit, CancellationToken ct)
    {
        var logs = await _db.Set<StaffPurchaseLog>()
            .Where(l => l.BusinessId == businessId)
            .OrderByDescending(l => l.CreatedAt)
            .Take(limit)
            .ToListAsync(ct);

        var userIds = logs.Where(l => l.UserId != Guid.Empty).Select(l => l.UserId).Distinct().ToHashSet();
        var userNames = await _db.Users.Where(u => userIds.Contains(u.Id)).ToDictionaryAsync(u => u.Id, u => u.Name ?? u.Username, ct);

        return logs.Select(l => new StaffPurchaseLogOut(
            l.Id, Guid.Empty, l.ItemName ?? "Unknown",
            l.Qty ?? 0, l.Amount, l.Unit, null, l.Notes,
            userNames.GetValueOrDefault(l.UserId), l.CreatedAt
        )).ToList();
    }

    public async Task<StaffPurchaseLogOut> CreateStaffPurchaseAsync(Guid businessId, StaffPurchaseLogIn request, Guid actorId, string actorName, CancellationToken ct)
    {
        var item = await _db.CatalogItems.FindAsync(new object[] { request.CatalogItemId }, ct)
            ?? throw new KeyNotFoundException("Item not found");

        var log = new StaffPurchaseLog
        {
            BusinessId = businessId, UserId = actorId,
            ItemName = item.Name, Qty = request.Qty, Unit = request.Unit,
            Amount = request.Rate, Notes = request.Notes,
        };
        _db.Set<StaffPurchaseLog>().Add(log);
        item.CurrentStock += request.Qty;
        item.LastStockUpdatedAt = DateTime.UtcNow;
        await _db.SaveChangesAsync(ct);

        return new StaffPurchaseLogOut(log.Id, item.Id, item.Name, request.Qty, request.Rate, request.Unit, null, request.Notes, actorName, log.CreatedAt);
    }

    private static string ComputeStockStatus(decimal currentStock, decimal reorderLevel)
    {
        if (currentStock < 0) return "critical";
        if (currentStock == 0) return "out_of_stock";
        if (currentStock <= reorderLevel) return "low";
        return "ok";
    }
}
