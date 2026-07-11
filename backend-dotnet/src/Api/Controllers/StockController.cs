using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PurchaseAssistant.Application.DTOs;
using PurchaseAssistant.Application.Interfaces;
using StockPatchIn = PurchaseAssistant.Application.DTOs.Stock.StockPatchIn;

namespace PurchaseAssistant.Api.Controllers;

[ApiController]
[Authorize]
[Route("v1/businesses/{businessId:guid}/stock")]
public class StockController : ControllerBase
{
    private readonly IStockService _stockService;

    public StockController(IStockService stockService)
    {
        _stockService = stockService;
    }

    // ---- 12a. Stock List ----
    [HttpGet("list")]
    public async Task<ActionResult<object>> GetStockList(
        Guid businessId,
        [FromQuery] Guid? categoryId,
        [FromQuery] Guid? typeId,
        [FromQuery] bool? lowStock,
        [FromQuery] string? q,
        [FromQuery] int page = 1,
        [FromQuery] int perPage = 50)
    {
        var role = User.FindFirstValue(ClaimTypes.Role) ?? "staff";
        var result = await _stockService.GetStockListAsync(businessId, categoryId, typeId, lowStock, q, page, perPage, role);
        return Ok(result);
    }

    [HttpGet("shell-bundle")]
    public IActionResult GetShellBundle(Guid businessId) => StatusCode(501);

    [HttpGet("delivery-indicator-counts")]
    public IActionResult GetDeliveryIndicatorCounts(Guid businessId) => StatusCode(501);

    [HttpGet("list/compact")]
    public IActionResult GetStockListCompact(Guid businessId) => StatusCode(501);

    [HttpGet("search")]
    public IActionResult SearchStock(Guid businessId) => StatusCode(501);

    [HttpGet("low")]
    public IActionResult GetLowStock(Guid businessId) => StatusCode(501);

    [HttpGet("critical")]
    public IActionResult GetCriticalStock(Guid businessId) => StatusCode(501);

    [HttpGet("alerts/summary")]
    public IActionResult GetAlertsSummary(Guid businessId) => StatusCode(501);

    [HttpGet("warehouse/alerts-summary")]
    public IActionResult GetWarehouseAlertsSummary(Guid businessId) => StatusCode(501);

    [HttpGet("low-stock/summary")]
    public IActionResult GetLowStockSummary(Guid businessId) => StatusCode(501);

    [HttpGet("low-stock/operations")]
    public IActionResult GetLowStockOperations(Guid businessId) => StatusCode(501);

    // ---- 12b. Stock Detail & Item Ops ----
    [HttpGet("items/{itemId:guid}/purchase-intelligence")]
    public IActionResult GetPurchaseIntelligence(Guid businessId, Guid itemId) => StatusCode(501);

    [HttpGet("{itemId:guid}/activity")]
    public IActionResult GetItemActivity(Guid businessId, Guid itemId) => StatusCode(501);

    [HttpGet("{itemId:guid}/intelligence")]
    public IActionResult GetItemIntelligence(Guid businessId, Guid itemId) => StatusCode(501);

    [HttpGet("item/{itemId:guid}/summary")]
    public IActionResult GetItemSummary(Guid businessId, Guid itemId) => StatusCode(501);

    [HttpGet("{itemId:guid}/bundle")]
    public IActionResult GetItemBundle(Guid businessId, Guid itemId) => StatusCode(501);

    [HttpGet("{itemId:guid}")]
    public async Task<ActionResult<object>> GetItemDetail(Guid businessId, Guid itemId)
    {
        try
        {
            var result = await _stockService.GetStockDetailAsync(businessId, itemId);
            return Ok(result);
        }
        catch (KeyNotFoundException)
        {
            return NotFound();
        }
    }

    [HttpPost("{itemId:guid}/opening-stock")]
    public IActionResult SetOpeningStock(Guid businessId, Guid itemId) => StatusCode(501);

    [HttpPost("{itemId:guid}/physical-count")]
    public async Task<ActionResult<object>> PhysicalCount(Guid businessId, Guid itemId, [FromBody] PhysicalStockCountIn request)
    {
        var actorId = Guid.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier) ?? Guid.Empty.ToString());
        var actorName = User.FindFirstValue(ClaimTypes.Name) ?? "unknown";
        try
        {
            var result = await _stockService.CreatePhysicalCountAsync(businessId, request with { ItemId = itemId }, actorId, actorName);
            return Ok(result);
        }
        catch (KeyNotFoundException)
        {
            return NotFound(new { message = "Catalog item not found" });
        }
    }

    [HttpPost("{itemId:guid}/physical-update")]
    public IActionResult PhysicalUpdate(Guid businessId, Guid itemId) => StatusCode(501);

    [HttpPost("{itemId:guid}/verify-count")]
    public IActionResult VerifyCount(Guid businessId, Guid itemId) => StatusCode(501);

    [HttpPatch("{itemId:guid}")]
    public async Task<ActionResult<object>> PatchStock(Guid businessId, Guid itemId, [FromBody] StockPatchIn request)
    {
        try
        {
            var actorId = Guid.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier) ?? Guid.Empty.ToString());
            var actorName = User.FindFirstValue(ClaimTypes.Name) ?? "unknown";
            var role = User.FindFirstValue(ClaimTypes.Role) ?? "staff";

            var result = await _stockService.PatchStockItemAsync(businessId, itemId, request, actorId, actorName, role);
            return Ok(result);
        }
        catch (KeyNotFoundException)
        {
            return NotFound(new { message = "Catalog item not found" });
        }
        catch (InvalidOperationException ex) when (ex.Message.StartsWith("Stock version conflict"))
        {
            return Conflict(new { message = ex.Message, code = "STALE_STOCK_VERSION_CONFLICT" });
        }
    }

    [HttpPost("{itemId:guid}/undo-last")]
    public IActionResult UndoLastAdjustment(Guid businessId, Guid itemId) => StatusCode(501);

    [HttpPost("{itemId:guid}/notify-owner")]
    public IActionResult NotifyOwner(Guid businessId, Guid itemId) => StatusCode(501);

    // ---- 12c. Stock Ops ----
    [HttpGet("opening/setup")]
    public IActionResult GetOpeningSetup(Guid businessId) => StatusCode(501);

    [HttpGet("inventory-summary")]
    public IActionResult GetInventorySummary(Guid businessId) => StatusCode(501);

    [HttpGet("totals")]
    public IActionResult GetTotals(Guid businessId) => StatusCode(501);

    [HttpGet("reorder")]
    public IActionResult GetReorderList(Guid businessId) => StatusCode(501);

    [HttpPatch("reorder/{entryId:guid}")]
    public IActionResult PatchReorderEntry(Guid businessId, Guid entryId) => StatusCode(501);

    [HttpDelete("reorder/{entryId:guid}")]
    public IActionResult DeleteReorderEntry(Guid businessId, Guid entryId) => StatusCode(501);

    [HttpGet("opening/missing")]
    public IActionResult GetOpeningMissing(Guid businessId) => StatusCode(501);

    [HttpPost("{itemId:guid}/quick-purchase")]
    public IActionResult QuickPurchase(Guid businessId, Guid itemId) => StatusCode(501);

    [HttpPost("{itemId:guid}/reorder")]
    public IActionResult AddToReorderList(Guid businessId, Guid itemId) => StatusCode(501);

    // ---- 12d. Stock Audit & Staff Purchases ----
    [HttpGet("audit/feed")]
    public IActionResult GetAuditFeed(Guid businessId) => StatusCode(501);

    [HttpGet("audit/recent")]
    public IActionResult GetAuditRecent(Guid businessId) => StatusCode(501);

    [HttpGet("variances/today")]
    public IActionResult GetVariancesToday(Guid businessId) => StatusCode(501);

    [HttpGet("audit/{itemId:guid}")]
    public IActionResult GetItemAudit(Guid businessId, Guid itemId) => StatusCode(501);

    [HttpGet("staff-purchases")]
    public IActionResult ListStaffPurchases(Guid businessId) => StatusCode(501);

    [HttpPost("staff-purchases")]
    public IActionResult CreateStaffPurchase(Guid businessId) => StatusCode(501);

    // ---- 12e. Barcode ----
    [HttpGet("barcode/lookup")]
    public IActionResult LookupBarcode(Guid businessId) => StatusCode(501);

    [HttpGet("barcode/{itemId:guid}")]
    public IActionResult GetBarcodeLabel(Guid businessId, Guid itemId) => StatusCode(501);

    [HttpPost("barcode/batch")]
    public IActionResult BatchBarcode(Guid businessId) => StatusCode(501);
}
