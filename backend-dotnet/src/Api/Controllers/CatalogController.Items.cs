using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using PurchaseAssistant.Application.DTOs.Catalog;
using PurchaseAssistant.Domain.Entities.Catalog;
using PurchaseAssistant.Domain.Entities.Trade;
using PurchaseAssistant.Infrastructure.Data;

namespace PurchaseAssistant.Api.Controllers;

// Catalog Items, Variants, Cross-entity endpoints
public partial class CatalogController
{
    // ==================== Catalog Items ====================

    [HttpGet("catalog-items")]
    public async Task<IActionResult> ListCatalogItems(Guid businessId,
        [FromQuery] Guid? categoryId = null, [FromQuery] Guid? typeId = null,
        [FromQuery] int page = 1, [FromQuery] int perPage = 200)
    {
        var query = _db.CatalogItems.Where(i => i.BusinessId == businessId && i.DeletedAt == null);

        if (categoryId != null) query = query.Where(i => i.CategoryId == categoryId.Value);
        if (typeId != null) query = query.Where(i => i.TypeId == typeId.Value);

        query = query.OrderBy(i => i.Name.ToLower()).Skip((page - 1) * perPage).Take(perPage);

        var items = await query.ToListAsync();
        var ids = items.Select(i => i.Id).ToList();

        var supMap = await DefaultSupplierBrokerIdsForItems(businessId, ids);
        var dateMap = await MaxPurchaseDatesForItems(businessId, ids);
        var tpIds = items.Where(i => i.LastTradePurchaseId != null).Select(i => i.LastTradePurchaseId!.Value).Distinct().ToList();
        var delMap = tpIds.Count > 0
            ? await _db.TradePurchases.Where(tp => tpIds.Contains(tp.Id))
                .ToDictionaryAsync(tp => tp.Id, tp => (tp.DeliveryStatus ?? "").ToLower() == "stock_committed")
            : new Dictionary<Guid, bool>();

        var catNames = await _db.ItemCategories.Where(c => c.BusinessId == businessId)
            .ToDictionaryAsync(c => c.Id, c => c.Name);

        var supNames = await _db.Suppliers.Where(s => s.BusinessId == businessId).ToDictionaryAsync(s => s.Id, s => s.Name);
        var broNames = await _db.Brokers.Where(b => b.BusinessId == businessId).ToDictionaryAsync(b => b.Id, b => b.Name);

        var outItems = items.Select(i =>
        {
            var entry = supMap.GetValueOrDefault(i.Id);
            var supIds = entry.SupIds ?? new List<Guid>();
            var broIds = entry.BroIds ?? new List<Guid>();
            return ToItemOut(i, null,
                defaultSupplierIds: supIds, defaultBrokerIds: broIds,
                lastSupplierName: i.LastSupplierId != null ? supNames.GetValueOrDefault(i.LastSupplierId.Value) : null,
                lastBrokerName: i.LastBrokerId != null ? broNames.GetValueOrDefault(i.LastBrokerId.Value) : null,
                categoryName: catNames.GetValueOrDefault(i.CategoryId),
                lastPurchaseDate: dateMap.GetValueOrDefault(i.Id),
                lastPurchaseDelivered: i.LastTradePurchaseId != null ? delMap.GetValueOrDefault(i.LastTradePurchaseId.Value) : null);
        }).ToList();

        return Ok(outItems);
    }

    [HttpPost("catalog-items")]
    public async Task<IActionResult> CreateCatalogItem(Guid businessId, [FromBody] CatalogItemCreateRequest body)
    {
        if (!await _db.ItemCategories.AnyAsync(c => c.Id == body.CategoryId && c.BusinessId == businessId))
            return BadRequest(new { detail = "category_id not found in this business" });

        Guid resolvedType;
        if (body.TypeId != null)
        {
            if (!await _db.CategoryTypes
                .Join(_db.ItemCategories.Where(c => c.BusinessId == businessId),
                    ct => ct.CategoryId, c => c.Id, (ct, _) => ct)
                .AnyAsync(ct => ct.Id == body.TypeId && ct.CategoryId == body.CategoryId))
                return BadRequest(new { detail = "type_id not found for this category" });
            resolvedType = body.TypeId.Value;
        }
        else
        {
            resolvedType = await GetOrCreateGeneralTypeId(businessId, body.CategoryId);
        }

        if (await ItemDup(businessId, body.CategoryId, resolvedType, body.Name, true))
        {
            var dupId = await _db.CatalogItems
                .Where(i => i.BusinessId == businessId && i.CategoryId == body.CategoryId
                    && i.Name.ToLower() == NormName(body.Name) && i.TypeId == resolvedType)
                .Select(i => (Guid?)i.Id).FirstOrDefaultAsync();
            return Conflict(new { message = "An item with this name already exists for this category and type",
                existing_item_id = dupId?.ToString() });
        }

        var u = body.DefaultUnit;
        var dkg = u is "bag" or "piece" ? (double?)body.DefaultKgPerBag : null;
        var dbox = u == "box" ? (double?)CoerceBoxItemsPerBox(body.DefaultItemsPerBox) : null;
        var dwt = u == "tin" ? body.DefaultWeightPerTin : null;
        var purchaseU = body.DefaultPurchaseUnit ?? body.DefaultUnit;
        var supplierIds = DedupePreserveOrder(body.DefaultSupplierIds);
        var brokerIds = DedupePreserveOrder(body.DefaultBrokerIds ?? new List<Guid>());

        try { await AssertSupplierIdsInBusiness(businessId, supplierIds); }
        catch { return BadRequest(new { detail = "One or more default_supplier_ids are invalid for this business" }); }
        try { await AssertBrokerIdsInBusiness(businessId, brokerIds); }
        catch { return BadRequest(new { detail = "One or more default_broker_ids are invalid for this business" }); }

        var finalItemCode = (body.ItemCode ?? "").Trim();
        if (string.IsNullOrEmpty(finalItemCode)) finalItemCode = await NextItemCode(businessId);
        var finalBarcode = (body.Barcode ?? "").Trim();
        if (string.IsNullOrEmpty(finalBarcode)) finalBarcode = finalItemCode;

        var item = new CatalogItem
        {
            BusinessId = businessId, CategoryId = body.CategoryId, TypeId = resolvedType,
            Name = body.Name.Trim(), DefaultUnit = u,
            DefaultKgPerBag = dkg.HasValue ? (decimal)dkg.Value : null,
            DefaultItemsPerBox = dbox.HasValue ? (decimal)dbox.Value : null,
            DefaultWeightPerTin = dwt.HasValue ? (decimal)dwt.Value : null,
            DefaultPurchaseUnit = purchaseU, DefaultSaleUnit = body.DefaultSaleUnit,
            HsnCode = (body.HsnCode ?? "").Trim() is { } h && h.Length > 0 ? h : null,
            ItemCode = finalItemCode, Barcode = finalBarcode,
            TaxPercent = body.TaxPercent.HasValue ? (decimal)body.TaxPercent.Value : null,
            DefaultLandingCost = body.DefaultLandingCost.HasValue ? (decimal)body.DefaultLandingCost.Value : null,
            DefaultSellingCost = body.DefaultSellingCost.HasValue ? (decimal)body.DefaultSellingCost.Value : null,
        };
        ApplyCanonicalUnitProfile(item, u);
        _db.CatalogItems.Add(item);
        await _db.SaveChangesAsync();

        await ReplaceDefaultSupplierRows(businessId, item.Id, supplierIds);
        await ReplaceDefaultBrokerRows(businessId, item.Id, brokerIds);
        await SeedSupplierItemDefaults(businessId, item.Id, supplierIds);
        await _db.SaveChangesAsync();

        var catName = await _db.ItemCategories.Where(c => c.Id == item.CategoryId).Select(c => c.Name).FirstOrDefaultAsync();
        var typeName = item.TypeId != null ? await _db.CategoryTypes.Where(t => t.Id == item.TypeId).Select(t => t.Name).FirstOrDefaultAsync() : null;

        return CreatedAtAction(nameof(GetCatalogItem), new { businessId, itemId = item.Id },
            ToItemOut(item, typeName, defaultSupplierIds: supplierIds, defaultBrokerIds: brokerIds, categoryName: catName));
    }

    [HttpPost("catalog-items/from-scan")]
    public async Task<IActionResult> CreateFromScan(Guid businessId, [FromBody] CatalogItemFromScanRequest body)
    {
        var typeRow = await _db.CategoryTypes
            .Join(_db.ItemCategories.Where(c => c.BusinessId == businessId),
                ct => ct.CategoryId, c => c.Id, (ct, _) => new { ct.Id, ct.CategoryId })
            .FirstOrDefaultAsync(x => x.Id == body.TypeId);
        if (typeRow == null) return BadRequest(new { detail = "type_id not found in this business" });

        if (await _db.CatalogItems.AnyAsync(i => i.BusinessId == businessId && i.Barcode == body.Barcode))
            return Conflict(new { detail = "Barcode already exists" });
        if (await _db.CatalogItems.AnyAsync(i => i.BusinessId == businessId && i.ItemCode!.ToUpper() == body.ItemCode.ToUpper()))
            return Conflict(new { detail = "Item code already exists" });
        if (await _db.CatalogItems.AnyAsync(i => i.BusinessId == businessId && i.CategoryId == typeRow.CategoryId
            && i.TypeId == body.TypeId && i.Name.ToLower() == NormName(body.Name)))
            return Conflict(new { detail = "An item with this name already exists for this subcategory" });

        var u = body.DefaultUnit;
        var dkg = u == "bag" ? (double?)body.DefaultKgPerBag : null;

        var item = new CatalogItem
        {
            BusinessId = businessId, CategoryId = typeRow.CategoryId, TypeId = body.TypeId,
            Name = body.Name.Trim(), DefaultUnit = u,
            DefaultKgPerBag = dkg.HasValue ? (decimal)dkg.Value : null,
            Barcode = body.Barcode, ItemCode = body.ItemCode,
        };
        _db.CatalogItems.Add(item);
        await _db.SaveChangesAsync();

        var catName = await _db.ItemCategories.Where(c => c.Id == item.CategoryId).Select(c => c.Name).FirstOrDefaultAsync();
        var typeName = item.TypeId != null ? await _db.CategoryTypes.Where(t => t.Id == item.TypeId).Select(t => t.Name).FirstOrDefaultAsync() : null;
        return CreatedAtAction(nameof(GetCatalogItem), new { businessId, itemId = item.Id },
            ToItemOut(item, typeName, categoryName: catName));
    }

    [HttpPost("catalog-items/batch")]
    public async Task<IActionResult> BatchCreate(Guid businessId, [FromBody] CatalogBatchCreateRequest body)
    {
        if (body.Items.Count > 80) return BadRequest(new { detail = "Maximum 80 items per batch" });

        var created = new List<CatalogItem>();
        var skipped = 0;

        foreach (var line in body.Items)
        {
            var typeRow = await _db.CategoryTypes
                .Join(_db.ItemCategories.Where(c => c.BusinessId == businessId),
                    ct => ct.CategoryId, c => c.Id, (ct, _) => new { ct.Id, ct.CategoryId })
                .FirstOrDefaultAsync(x => x.Id == line.TypeId);
            if (typeRow == null) { skipped++; continue; }

            if (await ItemDup(businessId, typeRow.CategoryId, line.TypeId, line.Name, true))
            { skipped++; continue; }

            var u = line.DefaultUnit;
            var supplierIds = DedupePreserveOrder(line.DefaultSupplierIds);
            try { await AssertSupplierIdsInBusiness(businessId, supplierIds); }
            catch { skipped++; continue; }

            var item = new CatalogItem
            {
                BusinessId = businessId, CategoryId = typeRow.CategoryId, TypeId = line.TypeId,
                Name = line.Name.Trim(), DefaultUnit = u, DefaultPurchaseUnit = u,
                DefaultKgPerBag = u == "bag" && line.DefaultKgPerBag.HasValue ? (decimal)line.DefaultKgPerBag.Value : null,
                DefaultItemsPerBox = u == "box" ? (decimal)CoerceBoxItemsPerBox(line.DefaultItemsPerBox) : null,
                DefaultWeightPerTin = u == "tin" && line.DefaultWeightPerTin.HasValue ? (decimal)line.DefaultWeightPerTin.Value : null,
            };
            _db.CatalogItems.Add(item);
            await _db.SaveChangesAsync();

            await ReplaceDefaultSupplierRows(businessId, item.Id, supplierIds);
            await SeedSupplierItemDefaults(businessId, item.Id, supplierIds);
            created.Add(item);
        }

        var typeNames = await _db.CategoryTypes.ToDictionaryAsync(t => t.Id, t => t.Name);
        var catNames = await _db.ItemCategories.ToDictionaryAsync(c => c.Id, c => c.Name);
        var outItems = created.Select(i => ToItemOut(i,
            i.TypeId != null ? typeNames.GetValueOrDefault(i.TypeId.Value) : null,
            categoryName: catNames.GetValueOrDefault(i.CategoryId))).ToList();

        return Created("", new CatalogBatchOut { Created = outItems.Count, Skipped = skipped, Items = outItems });
    }

    [HttpGet("catalog-items/{itemId:guid}")]
    public async Task<IActionResult> GetCatalogItem(Guid businessId, Guid itemId)
    {
        var item = await _db.CatalogItems.FirstOrDefaultAsync(i => i.Id == itemId && i.BusinessId == businessId);
        if (item == null) return NotFound(new { detail = "Item not found" });

        var typeName = item.TypeId != null ? await _db.CategoryTypes.Where(t => t.Id == item.TypeId).Select(t => t.Name).FirstOrDefaultAsync() : null;
        var catName = await _db.ItemCategories.Where(c => c.Id == item.CategoryId).Select(c => c.Name).FirstOrDefaultAsync();

        var (supIds, broIds) = (await DefaultSupplierBrokerIdsForItems(businessId, new List<Guid> { itemId }))
            .GetValueOrDefault(itemId, (new List<Guid>(), new List<Guid>()));

        string? lastSupName = null, lastBroName = null;
        if (item.LastSupplierId != null)
            lastSupName = await _db.Suppliers.Where(s => s.Id == item.LastSupplierId).Select(s => s.Name).FirstOrDefaultAsync();
        if (item.LastBrokerId != null)
            lastBroName = await _db.Brokers.Where(b => b.Id == item.LastBrokerId).Select(b => b.Name).FirstOrDefaultAsync();

        var lastPurchaseDate = await MaxPurchaseDateForItem(businessId, itemId);
        bool? lastPurchaseDelivered = null;
        if (item.LastTradePurchaseId != null)
        {
            var tp = await _db.TradePurchases.FirstOrDefaultAsync(t => t.Id == item.LastTradePurchaseId);
            lastPurchaseDelivered = tp != null && (tp.DeliveryStatus ?? "").ToLower() == "stock_committed";
        }

        return Ok(ToItemOut(item, typeName,
            defaultSupplierIds: supIds, defaultBrokerIds: broIds,
            lastSupplierName: lastSupName, lastBrokerName: lastBroName,
            categoryName: catName, lastPurchaseDate: lastPurchaseDate, lastPurchaseDelivered: lastPurchaseDelivered));
    }

    [HttpPatch("catalog-items/{itemId:guid}")]
    public async Task<IActionResult> UpdateCatalogItem(Guid businessId, Guid itemId, [FromBody] CatalogItemUpdateRequest body)
    {
        var item = await _db.CatalogItems.FirstOrDefaultAsync(i => i.Id == itemId && i.BusinessId == businessId);
        if (item == null) return NotFound(new { detail = "Item not found" });

        var cid = item.CategoryId;
        var tid = item.TypeId;

        if (body.CategoryId != null)
        {
            if (!await _db.ItemCategories.AnyAsync(c => c.Id == body.CategoryId && c.BusinessId == businessId))
                return BadRequest(new { detail = "category_id not found" });
            item.CategoryId = body.CategoryId.Value;
            cid = item.CategoryId;
            if (body.TypeId == null)
            {
                item.TypeId = await GetOrCreateGeneralTypeId(businessId, cid);
                tid = item.TypeId;
            }
        }

        if (body.TypeId != null)
        {
            if (!await _db.CategoryTypes
                .Join(_db.ItemCategories.Where(c => c.BusinessId == businessId),
                    ct => ct.CategoryId, c => c.Id, (ct, _) => ct)
                .AnyAsync(ct => ct.Id == body.TypeId && ct.CategoryId == cid))
                return BadRequest(new { detail = "type_id not found for this category" });
            item.TypeId = body.TypeId;
            tid = item.TypeId;
        }

        if (body.Name != null)
        {
            if (await ItemDup(businessId, cid, tid, body.Name, true, itemId))
            {
                var dupId = await _db.CatalogItems
                    .Where(i => i.BusinessId == businessId && i.CategoryId == cid
                        && i.Name.ToLower() == NormName(body.Name) && i.Id != itemId)
                    .Select(i => (Guid?)i.Id).FirstOrDefaultAsync();
                return Conflict(new { message = "An item with this name already exists for this category and type",
                    existing_item_id = dupId?.ToString() });
            }
            item.Name = body.Name.Trim();
        }

        if (body.DefaultUnit != null)
        {
            item.DefaultUnit = body.DefaultUnit;
            if (body.DefaultUnit != "bag") item.DefaultKgPerBag = null;
            if (body.DefaultUnit != "box") item.DefaultItemsPerBox = null;
            if (body.DefaultUnit != "tin") item.DefaultWeightPerTin = null;
        }
        if (body.DefaultKgPerBag != null && item.DefaultUnit == "bag")
            item.DefaultKgPerBag = (decimal)body.DefaultKgPerBag.Value;
        if (body.DefaultItemsPerBox != null && item.DefaultUnit == "box")
            item.DefaultItemsPerBox = (decimal)CoerceBoxItemsPerBox(body.DefaultItemsPerBox);
        if (body.DefaultWeightPerTin != null && item.DefaultUnit == "tin")
            item.DefaultWeightPerTin = (decimal)body.DefaultWeightPerTin.Value;
        if (body.DefaultPurchaseUnit != null) item.DefaultPurchaseUnit = body.DefaultPurchaseUnit;
        if (body.DefaultSaleUnit != null) item.DefaultSaleUnit = body.DefaultSaleUnit;
        if (body.HsnCode != null) item.HsnCode = (body.HsnCode ?? "").Trim() is { } h && h.Length > 0 ? h : null;
        if (body.TaxPercent != null) item.TaxPercent = (decimal)body.TaxPercent.Value;
        if (body.DefaultLandingCost != null) item.DefaultLandingCost = (decimal)body.DefaultLandingCost.Value;
        if (body.DefaultSellingCost != null) item.DefaultSellingCost = (decimal)body.DefaultSellingCost.Value;
        if (body.ReorderLevel != null) item.ReorderLevel = (decimal)body.ReorderLevel.Value;

        SyncItemUnitExtras(item);

        if (body.DefaultSupplierIds != null)
        {
            var sids = DedupePreserveOrder(body.DefaultSupplierIds);
            try { await AssertSupplierIdsInBusiness(businessId, sids); }
            catch { return BadRequest(new { detail = "One or more default_supplier_ids are invalid for this business" }); }
            await ReplaceDefaultSupplierRows(businessId, itemId, sids);
            await SeedSupplierItemDefaults(businessId, itemId, sids);
        }
        if (body.DefaultBrokerIds != null)
        {
            var bids = DedupePreserveOrder(body.DefaultBrokerIds);
            try { await AssertBrokerIdsInBusiness(businessId, bids); }
            catch { return BadRequest(new { detail = "One or more default_broker_ids are invalid for this business" }); }
            await ReplaceDefaultBrokerRows(businessId, itemId, bids);
        }

        await _db.SaveChangesAsync();

        var typeName = item.TypeId != null ? await _db.CategoryTypes.Where(t => t.Id == item.TypeId).Select(t => t.Name).FirstOrDefaultAsync() : null;
        var catName = await _db.ItemCategories.Where(c => c.Id == item.CategoryId).Select(c => c.Name).FirstOrDefaultAsync();
        var (supIds, broIds) = (await DefaultSupplierBrokerIdsForItems(businessId, new List<Guid> { itemId }))
            .GetValueOrDefault(itemId, (new List<Guid>(), new List<Guid>()));

        string? lastSupName = null, lastBroName = null;
        if (item.LastSupplierId != null)
            lastSupName = await _db.Suppliers.Where(s => s.Id == item.LastSupplierId).Select(s => s.Name).FirstOrDefaultAsync();
        if (item.LastBrokerId != null)
            lastBroName = await _db.Brokers.Where(b => b.Id == item.LastBrokerId).Select(b => b.Name).FirstOrDefaultAsync();

        return Ok(ToItemOut(item, typeName, defaultSupplierIds: supIds, defaultBrokerIds: broIds,
            lastSupplierName: lastSupName, lastBrokerName: lastBroName, categoryName: catName));
    }

    [HttpDelete("catalog-items/{itemId:guid}")]
    public async Task<IActionResult> DeleteCatalogItem(Guid businessId, Guid itemId)
    {
        var item = await _db.CatalogItems.FirstOrDefaultAsync(i => i.Id == itemId && i.BusinessId == businessId);
        if (item == null) return NotFound(new { detail = "Item not found" });
        if (await _db.TradePurchaseLines.AnyAsync(l => l.CatalogItemId == itemId))
            return BadRequest(new { detail = "Cannot delete a catalog item that is linked to wholesale purchase lines" });

        _db.CatalogItems.Remove(item);
        await _db.SaveChangesAsync();
        return NoContent();
    }

    // ==================== Item Code / Barcode ====================

    [HttpPatch("catalog-items/{itemId:guid}/item-code")]
    public async Task<IActionResult> UpdateItemCode(Guid businessId, Guid itemId, [FromBody] ItemCodePatchRequest body)
    {
        var item = await _db.CatalogItems.FirstOrDefaultAsync(i => i.Id == itemId && i.BusinessId == businessId && i.DeletedAt == null);
        if (item == null) return NotFound(new { detail = "Item not found" });
        if (await _db.CatalogItems.AnyAsync(i => i.BusinessId == businessId && i.ItemCode!.ToUpper() == body.ItemCode.ToUpper() && i.Id != itemId))
            return Conflict(new { detail = "Item code already exists" });

        item.ItemCode = body.ItemCode;
        await _db.SaveChangesAsync();

        var typeName = item.TypeId != null ? await _db.CategoryTypes.Where(t => t.Id == item.TypeId).Select(t => t.Name).FirstOrDefaultAsync() : null;
        return Ok(ToItemOut(item, typeName));
    }

    [HttpPatch("catalog-items/{itemId:guid}/barcode")]
    public async Task<IActionResult> UpdateBarcode(Guid businessId, Guid itemId, [FromBody] BarcodePatchRequest body)
    {
        var item = await _db.CatalogItems.FirstOrDefaultAsync(i => i.Id == itemId && i.BusinessId == businessId && i.DeletedAt == null);
        if (item == null) return NotFound(new { detail = "Item not found" });

        if (!string.IsNullOrEmpty(body.Barcode) && await _db.CatalogItems.AnyAsync(i => i.BusinessId == businessId && i.Barcode == body.Barcode && i.Id != itemId))
            return Conflict(new { detail = "Barcode already exists" });

        item.Barcode = body.Barcode;
        await _db.SaveChangesAsync();

        var typeName = item.TypeId != null ? await _db.CategoryTypes.Where(t => t.Id == item.TypeId).Select(t => t.Name).FirstOrDefaultAsync() : null;
        return Ok(ToItemOut(item, typeName));
    }

    [HttpPost("catalog-items/{itemId:guid}/generate-code")]
    public async Task<IActionResult> GenerateCode(Guid businessId, Guid itemId)
    {
        var item = await _db.CatalogItems.FirstOrDefaultAsync(i => i.Id == itemId && i.BusinessId == businessId);
        if (item == null) return NotFound(new { detail = "Item not found" });
        if (!string.IsNullOrEmpty(item.ItemCode))
            return Conflict(new { message = "Item already has a code", item_code = item.ItemCode });

        item.ItemCode = await NextItemCode(businessId);
        await _db.SaveChangesAsync();

        var typeName = item.TypeId != null ? await _db.CategoryTypes.Where(t => t.Id == item.TypeId).Select(t => t.Name).FirstOrDefaultAsync() : null;
        var catName = await _db.ItemCategories.Where(c => c.Id == item.CategoryId).Select(c => c.Name).FirstOrDefaultAsync();
        var (supIds, broIds) = (await DefaultSupplierBrokerIdsForItems(businessId, new List<Guid> { itemId }))
            .GetValueOrDefault(itemId, (new List<Guid>(), new List<Guid>()));

        return Ok(ToItemOut(item, typeName, defaultSupplierIds: supIds, defaultBrokerIds: broIds, categoryName: catName));
    }

    // ==================== Supplier Defaults ====================

    [HttpGet("catalog-items/{itemId:guid}/supplier-purchase-defaults")]
    public async Task<IActionResult> GetSupplierDefaults(Guid businessId, Guid itemId, [FromQuery] Guid supplierId)
    {
        var item = await _db.CatalogItems.FirstOrDefaultAsync(i => i.Id == itemId && i.BusinessId == businessId);
        if (item == null) return NotFound(new { detail = "Item not found" });
        if (!await _db.Suppliers.AnyAsync(s => s.Id == supplierId && s.BusinessId == businessId))
            return NotFound(new { detail = "Supplier not found" });

        var d = await _db.SupplierItemDefaults.FirstOrDefaultAsync(x =>
            x.BusinessId == businessId && x.SupplierId == supplierId && x.CatalogItemId == itemId);

        return Ok(new SupplierPurchaseDefaultsOut
        {
            CatalogItemId = item.Id, SupplierId = supplierId,
            LastPrice = d?.LastPrice != null ? (double)d.LastPrice : null,
            LastDiscount = d?.LastDiscount != null ? (double)d.LastDiscount : null,
            LastPaymentDays = d?.LastPaymentDays, PurchaseCount = d?.PurchaseCount ?? 0,
            ItemHsnCode = item.HsnCode,
            ItemTaxPercent = item.TaxPercent != null ? (double)item.TaxPercent : null,
            ItemDefaultUnit = item.DefaultUnit,
            ItemDefaultKgPerBag = item.DefaultKgPerBag != null ? (double)item.DefaultKgPerBag : null,
            ItemDefaultLandingCost = item.DefaultLandingCost != null ? (double)item.DefaultLandingCost : null,
            ItemDefaultPurchaseUnit = item.DefaultPurchaseUnit ?? item.DefaultUnit,
        });
    }

    // ==================== Trade Supplier Prices ====================

    [HttpGet("catalog-items/{itemId:guid}/trade-supplier-prices")]
    public async Task<IActionResult> GetTradeSupplierPrices(Guid businessId, Guid itemId)
    {
        if (!await _db.CatalogItems.AnyAsync(i => i.Id == itemId && i.BusinessId == businessId))
            return NotFound(new { detail = "Item not found" });

        var lineRows = await _db.TradePurchaseLines
            .Where(l => l.CatalogItemId == itemId)
            .Join(_db.TradePurchases.Where(tp => tp.BusinessId == businessId && tp.SupplierId != null && tp.Status == "confirmed"),
                l => l.TradePurchaseId, tp => tp.Id, (l, tp) => new { l, tp })
    .Join(_db.Suppliers, x => x.tp.SupplierId, s => s.Id, (x, s) => new
    {
        x.tp.Id,
        SupplierId = x.tp.SupplierId!.Value,
        x.tp.PurchaseDate,
        x.l.LandingCost, x.l.Qty, x.l.Unit, x.l.LineTotal,
        LineId = x.l.Id, s.Name,
    })
            .OrderByDescending(x => x.PurchaseDate).ThenByDescending(x => x.LineId)
            .ToListAsync();

        var seenSuppliers = new HashSet<Guid>();
        var supplierLatest = new List<(Guid SupplierId, string Name, double LandingCost, string Unit, DateOnly PurchaseDate)>();
        var sumAmt = new Dictionary<Guid, double>();
        var sumQty = new Dictionary<Guid, double>();
        var deals = new Dictionary<Guid, HashSet<Guid>>();
        var landingForAvg = new List<double>();
        var lastFivePrices = new List<double>();

        foreach (var row in lineRows)
        {
            var lc = (double)row.LandingCost;
            var qty = (double)row.Qty;
            var la = (double)(row.LineTotal ?? 0);

            sumAmt[row.SupplierId] = sumAmt.GetValueOrDefault(row.SupplierId) + la;
            sumQty[row.SupplierId] = sumQty.GetValueOrDefault(row.SupplierId) + qty;
            deals.TryAdd(row.SupplierId, new HashSet<Guid>());
            deals[row.SupplierId].Add(row.Id);
            landingForAvg.Add(lc);
            if (lastFivePrices.Count < 5) lastFivePrices.Add(lc);
            if (seenSuppliers.Add(row.SupplierId))
                supplierLatest.Add((row.SupplierId, row.Name, lc, row.Unit, row.PurchaseDate));
        }

        var vwap = sumAmt.ToDictionary(kv => kv.Key, kv =>
        {
            var qn = sumQty.GetValueOrDefault(kv.Key);
            return qn > 1e-12 ? kv.Value / qn : (double?)null;
        });

        Guid? bestSupplier = null;
        var eligible = sumAmt.Keys.Where(sid =>
            (deals.GetValueOrDefault(sid)?.Count ?? 0) >= 2 &&
            vwap.GetValueOrDefault(sid) != null && sumQty.GetValueOrDefault(sid) > 1e-12).ToList();
        if (eligible.Count > 0)
            bestSupplier = eligible.OrderBy(s => vwap.GetValueOrDefault(s)).ThenBy(s => s).First();
        else if (supplierLatest.Count > 0)
            bestSupplier = supplierLatest.OrderBy(r => r.LandingCost).ThenBy(r => r.SupplierId).First().SupplierId;

        var suppliers = supplierLatest.GroupBy(r => r.SupplierId).Select(g =>
        {
            var r = g.First();
            return new TradeSupplierPriceRow
            {
                SupplierId = r.SupplierId, SupplierName = r.Name, LandingCost = r.LandingCost,
                Unit = r.Unit, LastPurchaseDate = r.PurchaseDate,
                IsBest = bestSupplier != null && r.SupplierId == bestSupplier,
                Deals = deals.GetValueOrDefault(r.SupplierId)?.Count ?? 0,
                VolumeWeightedLanding = vwap.GetValueOrDefault(r.SupplierId),
            };
        }).OrderBy(s => !s.IsBest).ThenBy(s => s.LandingCost).ThenBy(s => s.SupplierName).ToList();

        return Ok(new CatalogItemTradeSupplierPricesOut
        {
            CatalogItemId = itemId, Suppliers = suppliers,
            LastFiveLandingPrices = lastFivePrices,
            AvgLandingFromTrade = landingForAvg.Count > 0 ? landingForAvg.Average() : null,
        });
    }

    // ==================== Item Insights ====================

    [HttpGet("catalog-items/{itemId:guid}/insights")]
    public async Task<IActionResult> GetItemInsights(Guid businessId, Guid itemId,
        [FromQuery(Name = "from")] DateOnly fromDate, [FromQuery(Name = "to")] DateOnly toDate)
    {
        if (!await _db.CatalogItems.AnyAsync(i => i.Id == itemId && i.BusinessId == businessId))
            return NotFound(new { detail = "Item not found" });

        var baseQuery = _db.TradePurchaseLines.Where(l => l.CatalogItemId == itemId)
            .Join(_db.TradePurchases.Where(tp => tp.BusinessId == businessId && tp.PurchaseDate >= fromDate && tp.PurchaseDate <= toDate),
                l => l.TradePurchaseId, tp => tp.Id, (l, _) => l);

        var lineCount = await baseQuery.CountAsync();
        var entryCount = await baseQuery.Select(l => l.TradePurchaseId).Distinct().CountAsync();
        var totalProfit = (double)(await baseQuery.SumAsync(l => l.Profit ?? 0));
        var avgLanding = (double?)await baseQuery.AverageAsync(l => (decimal?)l.LandingCost);
        var avgSelling = (double?)(await baseQuery.AverageAsync(l => (decimal?)(l.SellingRate ?? l.SellingCost)));
        var lastEntry = await baseQuery.Join(_db.TradePurchases, l => l.TradePurchaseId, tp => tp.Id, (_, tp) => tp)
            .MaxAsync(tp => (DateOnly?)tp.PurchaseDate);

        double? profitMarginPct = null;
        if (lineCount > 0)
        {
            var totalRev = (double)(await baseQuery.SumAsync(l => l.Qty * (l.SellingRate ?? l.SellingCost)) ?? 0);
            if (totalRev > 0) profitMarginPct = (totalProfit / totalRev) * 100.0;
        }

        return Ok(new CatalogItemInsightsOut
        {
            LineCount = lineCount, EntryCount = entryCount, TotalProfit = totalProfit,
            AvgLanding = avgLanding, AvgSelling = avgSelling, LastEntryDate = lastEntry, ProfitMarginPct = profitMarginPct,
        });
    }

    // ==================== Item Lines ====================

    [HttpGet("catalog-items/{itemId:guid}/lines")]
    public async Task<IActionResult> GetItemLines(Guid businessId, Guid itemId,
        [FromQuery(Name = "from")] DateOnly fromDate, [FromQuery(Name = "to")] DateOnly toDate,
        [FromQuery] int limit = 20, [FromQuery] int offset = 0)
    {
        if (!await _db.CatalogItems.AnyAsync(i => i.Id == itemId && i.BusinessId == businessId))
            return NotFound(new { detail = "Item not found" });

        var cap = Math.Min(500, Math.Max(limit + offset, 1) * 4 + 20);
        var rows = await _db.TradePurchaseLines.Where(l => l.CatalogItemId == itemId)
            .Join(_db.TradePurchases.Where(tp => tp.BusinessId == businessId && tp.PurchaseDate >= fromDate && tp.PurchaseDate <= toDate),
                l => l.TradePurchaseId, tp => tp.Id, (l, tp) => new { l, tp })
            .GroupJoin(_db.Suppliers, x => x.tp.SupplierId, s => s.Id, (x, ss) => new { x.l, x.tp, Supplier = ss.FirstOrDefault() })
            .GroupJoin(_db.Brokers, x => x.tp.BrokerId, b => b.Id, (x, bs) => new { x.l, x.tp, x.Supplier, Broker = bs.FirstOrDefault() })
            .OrderByDescending(x => x.tp.PurchaseDate).ThenByDescending(x => x.l.Id)
            .Take(cap)
            .ToListAsync();

        var tradeRows = rows.Select(x => new CatalogItemLineRow
        {
            EntryId = x.l.Id, EntryDate = x.tp.PurchaseDate,
            Qty = (double)x.l.Qty, Unit = x.l.Unit, LandingCost = (double)x.l.LandingCost,
            SellingPrice = (double?)(x.l.SellingRate ?? x.l.SellingCost),
            Profit = (double?)x.l.Profit,
            SupplierName = x.Supplier?.Name, SupplierPhone = x.Supplier?.Phone,
            BrokerName = x.Broker?.Name, BrokerPhone = x.Broker?.Phone,
            PurchaseHumanId = x.tp.HumanId,
            KgPerUnit = x.l.KgPerUnit != null ? (double)x.l.KgPerUnit : null,
            LandingCostPerKg = x.l.LandingCostPerKg != null ? (double)x.l.LandingCostPerKg : null,
        }).OrderByDescending(r => r.EntryDate).ThenByDescending(r => r.EntryId).ToList();

        var page = tradeRows.Skip(offset).Take(limit).ToList();
        return Ok(page);
    }

    // ==================== Cross-entity catalog endpoints ====================

    [HttpGet("catalog/fuzzy-check")]
    public async Task<IActionResult> FuzzyCheck(Guid businessId,
        [FromQuery] string name,
        [FromQuery] Guid? supplierId = null,
        [FromQuery] Guid? categoryId = null,
        [FromQuery] Guid? typeId = null)
    {
        var query = _db.CatalogItems.Where(i => i.BusinessId == businessId && i.DeletedAt == null);
        if (categoryId != null) query = query.Where(i => i.CategoryId == categoryId);
        if (typeId != null) query = query.Where(i => i.TypeId == typeId);
        if (supplierId != null)
            query = query.Where(i => _db.CatalogItemDefaultSuppliers.Any(ds =>
                ds.CatalogItemId == i.Id && ds.SupplierId == supplierId));

        var rows = await query.Select(i => new { i.Id, i.Name }).ToListAsync();
        var pairs = rows.Where(r => !string.IsNullOrEmpty(r.Name))
            .Select(r => (Id: r.Id, Name: r.Name)).ToList();

        var ranked = RankIdsByTokenSort(name.Trim(), pairs, 12, 55);
        var idToName = pairs.ToDictionary(p => p.Id, p => p.Name);
        var hits = ranked.Select(r => new CatalogFuzzyHit
        {
            Id = r.Id, Name = idToName.GetValueOrDefault(r.Id) ?? "", Score = Math.Round(r.Score / 100.0, 4),
        }).ToList();

        return Ok(new CatalogFuzzyCheckResponse { Hits = hits });
    }

    [HttpGet("catalog/duplicate-clusters")]
    public async Task<IActionResult> DuplicateClusters(Guid businessId, [FromQuery] double minScore = 0.85)
    {
        var rows = await _db.CatalogItems
            .Where(i => i.BusinessId == businessId && i.DeletedAt == null)
            .Select(i => new { i.Id, i.Name })
            .ToListAsync();

        var items = rows.Where(r => !string.IsNullOrEmpty(r.Name)).Select(r => (Id: r.Id, Name: r.Name.Trim())).ToList();
        var cutoff = (int)(minScore * 100);
        var pairs = new List<CatalogDuplicatePair>();

        for (int i = 0; i < items.Count; i++)
        {
            for (int j = i + 1; j < items.Count; j++)
            {
                var sc = FuzzyTokenSortRatio(items[i].Name.ToLower(), items[j].Name.ToLower());
                if (sc >= cutoff)
                {
                    pairs.Add(new CatalogDuplicatePair
                    {
                        IdA = items[i].Id, NameA = items[i].Name,
                        IdB = items[j].Id, NameB = items[j].Name,
                        Score = Math.Round(sc / 100.0, 4),
                    });
                }
            }
        }

        pairs = pairs.OrderByDescending(p => p.Score).Take(80).ToList();
        return Ok(new CatalogDuplicateClustersResponse { Pairs = pairs });
    }

    [HttpPost("catalog/items/bulk-archive")]
    public async Task<IActionResult> BulkArchive(Guid businessId, [FromBody] BulkItemIdsIn body)
    {
        var items = await _db.CatalogItems
            .Where(i => i.BusinessId == businessId && body.ItemIds.Contains(i.Id) && i.DeletedAt == null)
            .ToListAsync();

        var now = DateTime.UtcNow;
        foreach (var item in items) item.DeletedAt = now;
        await _db.SaveChangesAsync();
        return NoContent();
    }

    [HttpPatch("catalog/items/bulk-reorder")]
    public async Task<IActionResult> BulkReorder(Guid businessId, [FromBody] BulkReorderIn body)
    {
        var items = await _db.CatalogItems
            .Where(i => i.BusinessId == businessId && body.ItemIds.Contains(i.Id) && i.DeletedAt == null)
            .ToListAsync();

        var updated = 0;
        foreach (var item in items)
        {
            item.ReorderLevel = (decimal)body.ReorderLevel;
            updated++;
        }
        await _db.SaveChangesAsync();
        return Ok(new { updated });
    }

    // ==================== Variants ====================

    [HttpGet("catalog-items/{itemId:guid}/variants")]
    public async Task<IActionResult> ListVariants(Guid businessId, Guid itemId)
    {
        if (!await _db.CatalogItems.AnyAsync(i => i.Id == itemId && i.BusinessId == businessId))
            return NotFound(new { detail = "Catalog item not found" });

        var rows = await _db.CatalogVariants
            .Where(v => v.BusinessId == businessId && v.CatalogItemId == itemId)
            .OrderBy(v => v.Name.ToLower()).ToListAsync();

        return Ok(rows.Select(v => new CatalogVariantOut
        {
            Id = v.Id, CatalogItemId = v.CatalogItemId, Name = v.Name,
            DefaultKgPerBag = v.DefaultKgPerBag != null ? (double)v.DefaultKgPerBag : null,
        }));
    }

    [HttpPost("catalog-items/{itemId:guid}/variants")]
    public async Task<IActionResult> CreateVariant(Guid businessId, Guid itemId, [FromBody] CatalogVariantCreateRequest body)
    {
        if (!await _db.CatalogItems.AnyAsync(i => i.Id == itemId && i.BusinessId == businessId))
            return NotFound(new { detail = "Catalog item not found" });

        if (await VariantDup(businessId, itemId, body.Name, null))
            return Conflict(new { detail = "A variant with this name already exists for this item" });

        var v = new CatalogVariant
        {
            BusinessId = businessId, CatalogItemId = itemId, Name = body.Name.Trim(),
            DefaultKgPerBag = body.DefaultKgPerBag.HasValue ? (decimal)body.DefaultKgPerBag.Value : null,
        };
        _db.CatalogVariants.Add(v);
        await _db.SaveChangesAsync();

        return Created("", new CatalogVariantOut
        {
            Id = v.Id, CatalogItemId = v.CatalogItemId, Name = v.Name,
            DefaultKgPerBag = v.DefaultKgPerBag != null ? (double)v.DefaultKgPerBag : null,
        });
    }

    [HttpPatch("catalog-items/{itemId:guid}/variants/{variantId:guid}")]
    public async Task<IActionResult> UpdateVariant(Guid businessId, Guid itemId, Guid variantId, [FromBody] CatalogVariantUpdateRequest body)
    {
        var v = await _db.CatalogVariants.FirstOrDefaultAsync(x =>
            x.Id == variantId && x.BusinessId == businessId && x.CatalogItemId == itemId);
        if (v == null) return NotFound(new { detail = "Variant not found" });

        if (body.Name != null)
        {
            if (await VariantDup(businessId, itemId, body.Name, variantId))
                return Conflict(new { detail = "A variant with this name already exists for this item" });
            v.Name = body.Name.Trim();
        }
        if (body.DefaultKgPerBag != null) v.DefaultKgPerBag = (decimal)body.DefaultKgPerBag.Value;

        await _db.SaveChangesAsync();
        return Ok(new CatalogVariantOut
        {
            Id = v.Id, CatalogItemId = v.CatalogItemId, Name = v.Name,
            DefaultKgPerBag = v.DefaultKgPerBag != null ? (double)v.DefaultKgPerBag : null,
        });
    }

    [HttpDelete("catalog-items/{itemId:guid}/variants/{variantId:guid}")]
    public async Task<IActionResult> DeleteVariant(Guid businessId, Guid itemId, Guid variantId)
    {
        var v = await _db.CatalogVariants.FirstOrDefaultAsync(x =>
            x.Id == variantId && x.BusinessId == businessId && x.CatalogItemId == itemId);
        if (v == null) return NotFound(new { detail = "Variant not found" });

        _db.CatalogVariants.Remove(v);
        await _db.SaveChangesAsync();
        return NoContent();
    }

    // ==================== Private helpers ====================

    private async Task<bool> VariantDup(Guid businessId, Guid catalogItemId, string name, Guid? excludeId)
    {
        var q = _db.CatalogVariants.Where(v =>
            v.BusinessId == businessId && v.CatalogItemId == catalogItemId && v.Name.ToLower() == NormName(name));
        if (excludeId.HasValue) q = q.Where(v => v.Id != excludeId.Value);
        return await q.AnyAsync();
    }

    private static List<(Guid Id, double Score)> RankIdsByTokenSort(
        string query, List<(Guid Id, string Name)> rows, int limit = 12, int scoreCutoff = 55)
    {
        if (string.IsNullOrWhiteSpace(query) || rows.Count == 0) return new();

        var q = query.ToLower().Trim();
        var scored = rows
            .Select(r => (r.Id, Score: (double)FuzzyTokenSortRatio(q, r.Name.ToLower())))
            .Where(r => r.Score >= scoreCutoff)
            .OrderByDescending(r => r.Score)
            .Take(limit)
            .ToList();
        return scored;
    }

    private static int FuzzyTokenSortRatio(string s1, string s2)
    {
        var t1 = TokenSort(s1);
        var t2 = TokenSort(s2);
        if (t1.Length == 0 && t2.Length == 0) return 100;
        return (int)Math.Round(LevenshteinSimilarity(t1, t2) * 100);
    }

    private static string TokenSort(string s)
    {
        var tokens = s.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        Array.Sort(tokens, StringComparer.Ordinal);
        return string.Join(" ", tokens);
    }

    private static double LevenshteinSimilarity(string s1, string s2)
    {
        if (s1 == s2) return 1.0;
        if (s1.Length == 0 || s2.Length == 0) return 0.0;

        var len1 = s1.Length;
        var len2 = s2.Length;
        var matrix = new int[len1 + 1, len2 + 1];

        for (int i = 0; i <= len1; i++) matrix[i, 0] = i;
        for (int j = 0; j <= len2; j++) matrix[0, j] = j;

        for (int i = 1; i <= len1; i++)
        {
            for (int j = 1; j <= len2; j++)
            {
                var cost = s1[i - 1] == s2[j - 1] ? 0 : 1;
                matrix[i, j] = Math.Min(
                    Math.Min(matrix[i - 1, j] + 1, matrix[i, j - 1] + 1),
                    matrix[i - 1, j - 1] + cost);
            }
        }

        var maxLen = Math.Max(len1, len2);
        return maxLen > 0 ? 1.0 - (double)matrix[len1, len2] / maxLen : 1.0;
    }
}
