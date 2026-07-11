using Microsoft.EntityFrameworkCore;
using PurchaseAssistant.Application.DTOs.Catalog;
using PurchaseAssistant.Domain.Entities.Catalog;
using PurchaseAssistant.Domain.Entities.Contacts;
using PurchaseAssistant.Infrastructure.Data;

namespace PurchaseAssistant.Api.Controllers;

// Partial helper methods for CatalogController
public partial class CatalogController
{
    private static string NormName(string s)
        => string.Join(" ", s.ToLower().Trim().Split(' ', StringSplitOptions.RemoveEmptyEntries));

    private static List<Guid> DedupePreserveOrder(List<Guid> ids)
    {
        var seen = new HashSet<Guid>();
        var result = new List<Guid>(ids.Count);
        foreach (var id in ids)
            if (seen.Add(id)) result.Add(id);
        return result;
    }

    private static double CoerceBoxItemsPerBox(double? value)
        => (value is > 0) ? value.Value : 1.0;

    private static void SyncItemUnitExtras(CatalogItem item)
    {
        var u = item.DefaultUnit;
        if (u != "bag") item.DefaultKgPerBag = null;
        if (u != "box") item.DefaultItemsPerBox = null;
        if (u != "tin") item.DefaultWeightPerTin = null;
    }

    private static void ValidateItemUnitConstraints(CatalogItem item)
    {
        var u = item.DefaultUnit;
        if (u == "bag" && (item.DefaultKgPerBag == null || item.DefaultKgPerBag <= 0))
            throw new InvalidOperationException("default_kg_per_bag is required and must be positive when default_unit is bag");
        if (u == "box" && (item.DefaultItemsPerBox == null || item.DefaultItemsPerBox <= 0))
            item.DefaultItemsPerBox = 1;
    }

    private static void ApplyCanonicalUnitProfile(CatalogItem item, string unit)
    {
        var u = (unit ?? "").Trim().ToLower();
        switch (u)
        {
            case "bag":
                item.PackageType ??= "SACK";
                item.StockUnit = "BAG";
                item.DisplayUnit = "BAG";
                item.SellingUnit = "BAG";
                if (item.DefaultKgPerBag != null)
                {
                    item.PackageSize = item.DefaultKgPerBag;
                    item.PackageMeasurement = "KG";
                }
                item.ValidationStatus = "unit_profile_verified";
                break;
            case "kg":
                item.PackageType ??= "LOOSE";
                item.StockUnit = "KG";
                item.DisplayUnit = "KG";
                item.SellingUnit = "KG";
                break;
            case "box":
                item.PackageType ??= "BOX";
                item.StockUnit = "BOX";
                item.DisplayUnit = "BOX";
                break;
            case "tin":
                item.PackageType ??= "TIN";
                item.StockUnit = "TIN";
                item.DisplayUnit = "TIN";
                break;
            case "piece":
                item.PackageType ??= "PIECE";
                item.StockUnit = "PIECE";
                item.DisplayUnit = "PC";
                item.SellingUnit = "PCS";
                if (item.DefaultKgPerBag != null)
                {
                    item.PackageSize = item.DefaultKgPerBag;
                    item.PackageMeasurement = "KG";
                }
                break;
        }
    }

    private async Task<bool> CategoryDup(Guid businessId, string name, Guid? excludeId)
    {
        var q = _db.ItemCategories.Where(c => c.BusinessId == businessId && c.Name.ToLower() == NormName(name));
        if (excludeId.HasValue) q = q.Where(c => c.Id != excludeId.Value);
        return await q.AnyAsync();
    }

    private async Task<bool> TypeNameDup(Guid categoryId, string name, Guid? excludeId)
    {
        var q = _db.CategoryTypes.Where(t => t.CategoryId == categoryId && t.Name.ToLower() == NormName(name));
        if (excludeId.HasValue) q = q.Where(t => t.Id != excludeId.Value);
        return await q.AnyAsync();
    }

    private async Task<bool> ItemDup(Guid businessId, Guid categoryId, Guid? typeId, string name, bool hasTypeCol, Guid? excludeId = null)
    {
        var q = _db.CatalogItems.Where(i =>
            i.BusinessId == businessId &&
            i.CategoryId == categoryId &&
            i.Name.ToLower() == NormName(name));
        if (hasTypeCol && typeId.HasValue)
            q = q.Where(i => i.TypeId == typeId.Value);
        else if (hasTypeCol)
            q = q.Where(i => i.TypeId == null);
        if (excludeId.HasValue) q = q.Where(i => i.Id != excludeId.Value);
        return await q.AnyAsync();
    }

    private async Task VerifyTypeInCategory(Guid businessId, Guid categoryId, Guid typeId)
    {
        var exists = await _db.CategoryTypes
            .Join(_db.ItemCategories.Where(c => c.BusinessId == businessId),
                ct => ct.CategoryId, c => c.Id, (ct, c) => ct)
            .AnyAsync(ct => ct.Id == typeId && ct.CategoryId == categoryId);
        if (!exists)
            throw new InvalidOperationException("type_id not found for this category");
    }

    private async Task<Guid> GetOrCreateGeneralTypeId(Guid businessId, Guid categoryId)
    {
        var existing = await _db.CategoryTypes
            .FirstOrDefaultAsync(t => t.CategoryId == categoryId && t.Name.ToLower() == "general");
        if (existing != null) return existing.Id;

        var catExists = await _db.ItemCategories.AnyAsync(c => c.Id == categoryId && c.BusinessId == businessId);
        if (!catExists) throw new InvalidOperationException("category_id not found in this business");

        var ct = new CategoryType { CategoryId = categoryId, Name = "General" };
        _db.CategoryTypes.Add(ct);
        await _db.SaveChangesAsync();
        return ct.Id;
    }

    private async Task AssertSupplierIdsInBusiness(Guid businessId, List<Guid> supplierIds)
    {
        if (supplierIds.Count == 0) return;
        var count = await _db.Suppliers.CountAsync(s => s.BusinessId == businessId && supplierIds.Contains(s.Id));
        if (count != supplierIds.Count)
            throw new InvalidOperationException("One or more default_supplier_ids are invalid for this business");
    }

    private async Task AssertBrokerIdsInBusiness(Guid businessId, List<Guid> brokerIds)
    {
        if (brokerIds.Count == 0) return;
        var count = await _db.Brokers.CountAsync(b => b.BusinessId == businessId && brokerIds.Contains(b.Id));
        if (count != brokerIds.Count)
            throw new InvalidOperationException("One or more default_broker_ids are invalid for this business");
    }

    private async Task<Dictionary<Guid, (List<Guid> SupIds, List<Guid> BroIds)>> DefaultSupplierBrokerIdsForItems(
        Guid businessId, List<Guid> itemIds)
    {
        var result = itemIds.ToDictionary(id => id, _ => (SupIds: new List<Guid>(), BroIds: new List<Guid>()));

        var supRows = await _db.CatalogItemDefaultSuppliers
            .Where(x => x.BusinessId == businessId && itemIds.Contains(x.CatalogItemId))
            .OrderBy(x => x.CatalogItemId).ThenBy(x => x.SortOrder).ThenBy(x => x.SupplierId)
            .ToListAsync();

        foreach (var row in supRows)
        {
            var t = result[row.CatalogItemId];
            t.SupIds.Add(row.SupplierId);
        }

        var broRows = await _db.CatalogItemDefaultBrokers
            .Where(x => x.BusinessId == businessId && itemIds.Contains(x.CatalogItemId))
            .OrderBy(x => x.CatalogItemId).ThenBy(x => x.SortOrder).ThenBy(x => x.BrokerId)
            .ToListAsync();

        foreach (var row in broRows)
        {
            var t = result[row.CatalogItemId];
            t.BroIds.Add(row.BrokerId);
        }

        return result;
    }

    private async Task ReplaceDefaultSupplierRows(Guid businessId, Guid catalogItemId, List<Guid> supplierIds)
    {
        var old = await _db.CatalogItemDefaultSuppliers
            .Where(x => x.BusinessId == businessId && x.CatalogItemId == catalogItemId)
            .ToListAsync();
        _db.CatalogItemDefaultSuppliers.RemoveRange(old);

        for (int i = 0; i < supplierIds.Count; i++)
        {
            _db.CatalogItemDefaultSuppliers.Add(new CatalogItemDefaultSupplier
            {
                BusinessId = businessId,
                CatalogItemId = catalogItemId,
                SupplierId = supplierIds[i],
                SortOrder = i,
            });
        }
    }

    private async Task ReplaceDefaultBrokerRows(Guid businessId, Guid catalogItemId, List<Guid> brokerIds)
    {
        var old = await _db.CatalogItemDefaultBrokers
            .Where(x => x.BusinessId == businessId && x.CatalogItemId == catalogItemId)
            .ToListAsync();
        _db.CatalogItemDefaultBrokers.RemoveRange(old);

        for (int i = 0; i < brokerIds.Count; i++)
        {
            _db.CatalogItemDefaultBrokers.Add(new CatalogItemDefaultBroker
            {
                BusinessId = businessId,
                CatalogItemId = catalogItemId,
                BrokerId = brokerIds[i],
                SortOrder = i,
            });
        }
    }

    private async Task SeedSupplierItemDefaults(Guid businessId, Guid catalogItemId, List<Guid> supplierIds)
    {
        foreach (var sid in supplierIds)
        {
            var exists = await _db.SupplierItemDefaults.AnyAsync(x =>
                x.BusinessId == businessId && x.CatalogItemId == catalogItemId && x.SupplierId == sid);
            if (!exists)
            {
                _db.SupplierItemDefaults.Add(new SupplierItemDefault
                {
                    BusinessId = businessId,
                    CatalogItemId = catalogItemId,
                    SupplierId = sid,
                    PurchaseCount = 0,
                });
            }
        }
    }

    private async Task<string> NextItemCode(Guid businessId)
    {
        var codes = await _db.CatalogItems
            .Where(i => i.BusinessId == businessId && i.ItemCode != null && i.ItemCode.StartsWith("ITM-"))
            .Select(i => i.ItemCode!)
            .ToListAsync();

        var maxN = 0;
        var re = new System.Text.RegularExpressions.Regex(@"^ITM-(\d+)$", System.Text.RegularExpressions.RegexOptions.IgnoreCase);
        foreach (var code in codes)
        {
            var m = re.Match(code.Trim());
            if (m.Success && int.TryParse(m.Groups[1].Value, out var n))
                maxN = Math.Max(maxN, n);
        }
        return $"ITM-{maxN + 1:D4}";
    }

    private async Task<DateOnly?> MaxPurchaseDateForItem(Guid businessId, Guid catalogItemId)
    {
        return await _db.TradePurchaseLines
            .Where(l => l.CatalogItemId == catalogItemId)
            .Join(_db.TradePurchases.Where(tp => tp.BusinessId == businessId),
                l => l.TradePurchaseId, tp => tp.Id, (l, tp) => tp.PurchaseDate)
            .MaxAsync(x => (DateOnly?)x);
    }

    private async Task<Dictionary<Guid, DateOnly?>> MaxPurchaseDatesForItems(Guid businessId, List<Guid> catalogItemIds)
    {
        if (catalogItemIds.Count == 0) return new();

        var results = await _db.TradePurchaseLines
            .Where(l => l.CatalogItemId != null && catalogItemIds.Contains(l.CatalogItemId.Value))
            .Join(_db.TradePurchases.Where(tp => tp.BusinessId == businessId),
                l => l.TradePurchaseId, tp => tp.Id, (l, tp) => new { l.CatalogItemId, tp.PurchaseDate })
            .GroupBy(x => x.CatalogItemId!.Value)
            .Select(g => new { CatalogItemId = g.Key, MaxDate = g.Max(x => (DateOnly?)x.PurchaseDate) })
            .ToListAsync();

        return results.ToDictionary(r => r.CatalogItemId, r => r.MaxDate);
    }

    private static CatalogItemOut ToItemOut(
        CatalogItem item,
        string? typeName,
        List<Guid>? defaultSupplierIds = null,
        List<Guid>? defaultBrokerIds = null,
        string? lastSupplierName = null,
        string? lastBrokerName = null,
        string? categoryName = null,
        DateOnly? lastPurchaseDate = null,
        bool? lastPurchaseDelivered = null)
    {
        return new CatalogItemOut
        {
            Id = item.Id,
            CategoryId = item.CategoryId,
            TypeId = item.TypeId,
            TypeName = typeName,
            Name = item.Name,
            DefaultUnit = item.DefaultUnit,
            DefaultKgPerBag = item.DefaultKgPerBag != null ? (double)item.DefaultKgPerBag : null,
            DefaultItemsPerBox = item.DefaultItemsPerBox != null ? (double)item.DefaultItemsPerBox : null,
            DefaultWeightPerTin = item.DefaultWeightPerTin != null ? (double)item.DefaultWeightPerTin : null,
            DefaultPurchaseUnit = item.DefaultPurchaseUnit,
            DefaultSaleUnit = item.DefaultSaleUnit,
            HsnCode = item.HsnCode,
            ItemCode = item.ItemCode,
            Barcode = item.Barcode,
            PublicToken = item.PublicToken,
            TaxPercent = item.TaxPercent != null ? (double)item.TaxPercent : null,
            DefaultLandingCost = item.DefaultLandingCost != null ? (double)item.DefaultLandingCost : null,
            DefaultSellingCost = item.DefaultSellingCost != null ? (double)item.DefaultSellingCost : null,
            LastPurchasePrice = item.LastPurchasePrice != null ? (double)item.LastPurchasePrice : null,
            LastSellingRate = item.LastSellingRate != null ? (double)item.LastSellingRate : null,
            LastSupplierId = item.LastSupplierId,
            LastBrokerId = item.LastBrokerId,
            LastTradePurchaseId = item.LastTradePurchaseId,
            LastLineQty = item.LastLineQty != null ? (double)item.LastLineQty : null,
            LastLineUnit = item.LastLineUnit,
            LastLineWeightKg = item.LastLineWeightKg != null ? (double)item.LastLineWeightKg : null,
            LastSupplierName = lastSupplierName,
            LastBrokerName = lastBrokerName,
            DefaultSupplierIds = defaultSupplierIds ?? new List<Guid>(),
            DefaultBrokerIds = defaultBrokerIds ?? new List<Guid>(),
            LastPurchaseDate = lastPurchaseDate,
            LastPurchaseDelivered = lastPurchaseDelivered,
        };
    }
}
