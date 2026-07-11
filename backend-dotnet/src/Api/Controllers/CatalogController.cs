using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using PurchaseAssistant.Application.DTOs.Catalog;
using PurchaseAssistant.Domain.Entities.Catalog;
using PurchaseAssistant.Domain.Entities.Core;
using PurchaseAssistant.Domain.Entities.Trade;
using PurchaseAssistant.Infrastructure.Data;

namespace PurchaseAssistant.Api.Controllers;

[ApiController]
[Authorize]
[Route("v1/businesses/{businessId:guid}")]
public partial class CatalogController : ControllerBase
{
    private readonly PurchaseAssistantDbContext _db;

    public CatalogController(PurchaseAssistantDbContext db) => _db = db;

    // ==================== Categories ====================

    [HttpGet("item-categories")]
    public async Task<IActionResult> ListCategories(Guid businessId)
    {
        var rows = await _db.ItemCategories
            .Where(c => c.BusinessId == businessId)
            .OrderBy(c => c.Name.ToLower())
            .ToListAsync();
        return Ok(rows.Select(c => new ItemCategoryOut { Id = c.Id, Name = c.Name }));
    }

    [HttpPost("item-categories")]
    public async Task<IActionResult> CreateCategory(Guid businessId, [FromBody] ItemCategoryCreateRequest body)
    {
        if (await CategoryDup(businessId, body.Name, null))
            return Conflict(new { detail = "A category with this name already exists" });

        var c = new ItemCategory { BusinessId = businessId, Name = body.Name.Trim() };
        _db.ItemCategories.Add(c);
        await _db.SaveChangesAsync();

        _db.CategoryTypes.Add(new CategoryType { CategoryId = c.Id, Name = "General" });
        await _db.SaveChangesAsync();

        return CreatedAtAction(nameof(GetCategory), new { businessId, categoryId = c.Id },
            new ItemCategoryOut { Id = c.Id, Name = c.Name });
    }

    [HttpGet("item-categories/{categoryId:guid}")]
    public async Task<IActionResult> GetCategory(Guid businessId, Guid categoryId)
    {
        var c = await _db.ItemCategories.FirstOrDefaultAsync(x => x.Id == categoryId && x.BusinessId == businessId);
        if (c == null) return NotFound(new { detail = "Category not found" });
        return Ok(new ItemCategoryOut { Id = c.Id, Name = c.Name });
    }

    [HttpPatch("item-categories/{categoryId:guid}")]
    public async Task<IActionResult> UpdateCategory(Guid businessId, Guid categoryId, [FromBody] ItemCategoryUpdateRequest body)
    {
        var c = await _db.ItemCategories.FirstOrDefaultAsync(x => x.Id == categoryId && x.BusinessId == businessId);
        if (c == null) return NotFound(new { detail = "Category not found" });

        if (body.Name != null)
        {
            if (await CategoryDup(businessId, body.Name, categoryId))
                return Conflict(new { detail = "A category with this name already exists" });
            c.Name = body.Name.Trim();
        }
        await _db.SaveChangesAsync();
        return Ok(new ItemCategoryOut { Id = c.Id, Name = c.Name });
    }

    [HttpDelete("item-categories/{categoryId:guid}")]
    public async Task<IActionResult> DeleteCategory(Guid businessId, Guid categoryId)
    {
        var c = await _db.ItemCategories.FirstOrDefaultAsync(x => x.Id == categoryId && x.BusinessId == businessId);
        if (c == null) return NotFound(new { detail = "Category not found" });

        if (await _db.CatalogItems.AnyAsync(x => x.CategoryId == categoryId))
            return BadRequest(new { detail = "Cannot delete a category that still has catalog items — delete or move items first" });

        _db.ItemCategories.Remove(c);
        await _db.SaveChangesAsync();
        return NoContent();
    }

    [HttpGet("item-categories/{categoryId:guid}/trade-summary")]
    public async Task<IActionResult> GetCategoryTradeSummary(Guid businessId, Guid categoryId)
    {
        if (!await _db.ItemCategories.AnyAsync(x => x.Id == categoryId && x.BusinessId == businessId))
            return NotFound(new { detail = "Category not found" });

        var items = await _db.CatalogItems
            .Where(i => i.BusinessId == businessId && i.CategoryId == categoryId)
            .OrderBy(i => i.Name.ToLower()).ToListAsync();

        var itemIds = items.Select(i => i.Id).ToList();
        var tpIds = items.Where(i => i.LastTradePurchaseId != null).Select(i => i.LastTradePurchaseId!.Value).ToList();

        var lines = await _db.TradePurchaseLines
            .Where(l => l.CatalogItemId != null && itemIds.Contains(l.CatalogItemId.Value))
            .Join(_db.TradePurchases.Where(tp => tp.BusinessId == businessId && tp.Status == "confirmed"),
                l => l.TradePurchaseId, tp => tp.Id, (l, tp) => new { l, tp })
            .ToListAsync();

        var sIds = items.Where(i => i.LastSupplierId != null).Select(i => i.LastSupplierId!.Value).ToHashSet();
        var bIds = items.Where(i => i.LastBrokerId != null).Select(i => i.LastBrokerId!.Value).ToHashSet();
        var sNames = await _db.Suppliers.Where(s => sIds.Contains(s.Id)).ToDictionaryAsync(s => s.Id, s => s.Name);
        var bNames = await _db.Brokers.Where(b => bIds.Contains(b.Id)).ToDictionaryAsync(b => b.Id, b => b.Name);
        var lastTp = tpIds.Count > 0
            ? await _db.TradePurchases.Where(tp => tpIds.Contains(tp.Id)).ToDictionaryAsync(tp => tp.Id, tp => tp.HumanId)
            : new Dictionary<Guid, string>();

        var rows = items.Select(i =>
        {
            var il = lines.Where(l => l.l.CatalogItemId == i.Id).ToList();
            return new CategoryTradeItemRow
            {
                CatalogItemId = i.Id, Name = i.Name,
                PeriodLineTotal = il.Sum(l => (double)(l.l.LineTotal ?? 0)),
                PeriodQtyBags = il.Where(l => new[] { "bag", "sack", "box" }.Contains(l.l.Unit.ToLower())).Sum(l => (double)l.l.Qty),
                PeriodWeightKg = il.Sum(l => (double)(l.l.TotalWeight ?? 0)),
                LastPurchasePrice = (double?)i.LastPurchasePrice,
                LastSellingRate = (double?)i.LastSellingRate,
                LastSupplierName = i.LastSupplierId != null ? sNames.GetValueOrDefault(i.LastSupplierId.Value) : null,
                LastBrokerName = i.LastBrokerId != null ? bNames.GetValueOrDefault(i.LastBrokerId.Value) : null,
                LastTradeHumanId = i.LastTradePurchaseId != null ? lastTp.GetValueOrDefault(i.LastTradePurchaseId.Value) : null,
            };
        }).ToList();

        return Ok(new CategoryTradeSummaryOut
        {
            ItemCount = rows.Count, TotalLineAmount = rows.Sum(r => r.PeriodLineTotal),
            TotalQtyBags = rows.Sum(r => r.PeriodQtyBags), TotalWeightKg = rows.Sum(r => r.PeriodWeightKg), Items = rows,
        });
    }

    [HttpGet("item-categories/{categoryId:guid}/insights")]
    public async Task<IActionResult> GetCategoryInsights(Guid businessId, Guid categoryId,
        [FromQuery(Name = "from")] DateOnly fromDate, [FromQuery(Name = "to")] DateOnly toDate)
    {
        if (!await _db.ItemCategories.AnyAsync(x => x.Id == categoryId && x.BusinessId == businessId))
            return NotFound(new { detail = "Category not found" });

        var itemCount = await _db.CatalogItems.CountAsync(i => i.BusinessId == businessId && i.CategoryId == categoryId);
        var itemIds = await _db.CatalogItems.Where(i => i.BusinessId == businessId && i.CategoryId == categoryId).Select(i => i.Id).ToListAsync();

        var dateFiltered = _db.TradePurchaseLines
            .Where(l => l.CatalogItemId != null && itemIds.Contains(l.CatalogItemId.Value))
            .Join(_db.TradePurchases.Where(tp => tp.BusinessId == businessId && tp.PurchaseDate >= fromDate && tp.PurchaseDate <= toDate),
                l => l.TradePurchaseId, tp => tp.Id, (l, tp) => l);

        var linkedLineCount = await dateFiltered.CountAsync();
        var perItem = await dateFiltered
            .GroupBy(l => l.CatalogItemId!.Value)
            .Select(g => new { Id = g.Key, Profit = (double)(g.Sum(l => l.Profit) ?? 0) })
            .ToListAsync();

        var profitByItem = perItem.ToDictionary(x => x.Id, x => x.Profit);
        var names = await _db.CatalogItems.Where(i => itemIds.Contains(i.Id)).ToDictionaryAsync(i => i.Id, i => i.Name);

        string? topName = null, worstName = null;
        double? topProfit = null, worstProfit = null;
        if (profitByItem.Count > 0)
        {
            var best = profitByItem.MaxBy(x => x.Value);
            topName = names.GetValueOrDefault(best.Key); topProfit = best.Value;
            var worst = profitByItem.MinBy(x => x.Value);
            worstName = names.GetValueOrDefault(worst.Key); worstProfit = worst.Value;
        }

        return Ok(new CategoryInsightsOut
        {
            ItemCount = itemCount, LinkedLineCount = linkedLineCount,
            TotalProfit = profitByItem.Values.Sum(),
            TopItemName = topName, TopItemProfit = topProfit,
            WorstItemName = worstName, WorstItemProfit = worstProfit,
        });
    }

    // ==================== Category Types ====================

    [HttpGet("item-categories/{categoryId:guid}/category-types")]
    public async Task<IActionResult> ListCategoryTypes(Guid businessId, Guid categoryId)
    {
        if (!await _db.ItemCategories.AnyAsync(c => c.Id == categoryId && c.BusinessId == businessId))
            return NotFound(new { detail = "Category not found" });

        var rows = await _db.CategoryTypes.Where(t => t.CategoryId == categoryId)
            .OrderBy(t => t.Name.ToLower()).ToListAsync();
        return Ok(rows.Select(t => new CategoryTypeOut { Id = t.Id, CategoryId = t.CategoryId, Name = t.Name }));
    }

    [HttpPost("item-categories/{categoryId:guid}/category-types")]
    public async Task<IActionResult> CreateCategoryType(Guid businessId, Guid categoryId, [FromBody] CategoryTypeCreateRequest body)
    {
        if (!await _db.ItemCategories.AnyAsync(c => c.Id == categoryId && c.BusinessId == businessId))
            return NotFound(new { detail = "Category not found" });

        if (await TypeNameDup(categoryId, body.Name, null))
            return Conflict(new { detail = "A type with this name already exists in this category" });

        var t = new CategoryType { CategoryId = categoryId, Name = body.Name.Trim() };
        _db.CategoryTypes.Add(t);
        await _db.SaveChangesAsync();
        return CreatedAtAction(nameof(ListCategoryTypes), new { businessId, categoryId },
            new CategoryTypeOut { Id = t.Id, CategoryId = t.CategoryId, Name = t.Name });
    }

    [HttpPatch("item-categories/{categoryId:guid}/category-types/{typeId:guid}")]
    public async Task<IActionResult> UpdateCategoryType(Guid businessId, Guid categoryId, Guid typeId, [FromBody] CategoryTypeUpdateRequest body)
    {
        var t = await _db.CategoryTypes
            .Join(_db.ItemCategories.Where(c => c.BusinessId == businessId),
                ct => ct.CategoryId, c => c.Id, (ct, _) => ct)
            .FirstOrDefaultAsync(ct => ct.Id == typeId && ct.CategoryId == categoryId);
        if (t == null) return NotFound(new { detail = "Type not found" });

        if (body.Name != null)
        {
            if (await TypeNameDup(categoryId, body.Name, typeId))
                return Conflict(new { detail = "A type with this name already exists in this category" });
            t.Name = body.Name.Trim();
        }
        await _db.SaveChangesAsync();
        return Ok(new CategoryTypeOut { Id = t.Id, CategoryId = t.CategoryId, Name = t.Name });
    }

    [HttpDelete("item-categories/{categoryId:guid}/category-types/{typeId:guid}")]
    public async Task<IActionResult> DeleteCategoryType(Guid businessId, Guid categoryId, Guid typeId)
    {
        var t = await _db.CategoryTypes
            .Join(_db.ItemCategories.Where(c => c.BusinessId == businessId),
                ct => ct.CategoryId, c => c.Id, (ct, _) => ct)
            .FirstOrDefaultAsync(ct => ct.Id == typeId && ct.CategoryId == categoryId);
        if (t == null) return NotFound(new { detail = "Type not found" });

        if (await _db.CatalogItems.AnyAsync(i => i.TypeId == typeId))
            return BadRequest(new { detail = "Cannot delete a type that still has catalog items — move or delete items first" });

        _db.CategoryTypes.Remove(t);
        await _db.SaveChangesAsync();
        return NoContent();
    }

    [HttpGet("category-types-index")]
    public async Task<IActionResult> GetCategoryTypesIndex(Guid businessId)
    {
        var rows = await _db.CategoryTypes
            .Join(_db.ItemCategories.Where(c => c.BusinessId == businessId),
                ct => ct.CategoryId, c => c.Id, (ct, c) => new { ct, CategoryName = c.Name })
            .OrderBy(x => x.CategoryName.ToLower()).ThenBy(x => x.ct.Name.ToLower())
            .ToListAsync();
        return Ok(rows.Select(x => new CategoryTypeIndexOut
        {
            Id = x.ct.Id, CategoryId = x.ct.CategoryId, CategoryName = x.CategoryName, Name = x.ct.Name,
        }));
    }
}
