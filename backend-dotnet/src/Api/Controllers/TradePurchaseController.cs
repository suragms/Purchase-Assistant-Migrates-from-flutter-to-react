using System.Security.Claims;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using PurchaseAssistant.Application.DTOs;
using PurchaseAssistant.Application.Services;

namespace PurchaseAssistant.Api.Controllers;

[ApiController]
[Authorize]
[Route("v1/businesses/{businessId:guid}/trade-purchases")]
public class TradePurchaseController : ControllerBase
{
    private readonly ITradePurchaseService _tradeService;

    public TradePurchaseController(ITradePurchaseService tradeService) => _tradeService = tradeService;

    private Guid GetUserId() => Guid.Parse(User.FindFirstValue(ClaimTypes.NameIdentifier)!);
    private string GetUserName() => User.FindFirstValue(ClaimTypes.Name) ?? User.FindFirstValue("name") ?? "";
    private string GetRole() => User.FindFirstValue("role") ?? "staff";

    // ─── Draft ────────────────────────────────────────────────

    [HttpGet("draft")]
    public async Task<ActionResult<TradeDraftOut>> GetDraft(Guid businessId)
    {
        var result = await _tradeService.GetDraftAsync(businessId, GetUserId());
        if (result is null) return NotFound(new { detail = "No draft" });
        return Ok(result);
    }

    [HttpPut("draft")]
    public async Task<ActionResult<TradeDraftOut>> UpsertDraft(Guid businessId, [FromBody] TradeDraftUpsertIn body)
    {
        var result = await _tradeService.UpsertDraftAsync(businessId, GetUserId(), body.Step, body.PayloadJson);
        return Ok(result);
    }

    [HttpDelete("draft")]
    public async Task<ActionResult> DeleteDraft(Guid businessId)
    {
        await _tradeService.DeleteDraftAsync(businessId, GetUserId());
        return NoContent();
    }

    // ─── Preview / Validate ───────────────────────────────────

    [HttpPost("preview-lines")]
    public async Task<ActionResult<TradePurchasePreviewOut>> PreviewLines(Guid businessId, [FromBody] TradePurchaseCreateIn body)
    {
        var result = await _tradeService.PreviewLinesAsync(businessId, body);
        return Ok(result);
    }

    [HttpPost("validate")]
    public async Task<ActionResult<TradePurchaseValidateOut>> Validate(Guid businessId, [FromBody] TradePurchaseCreateIn body)
    {
        var result = await _tradeService.ValidatePurchaseAsync(businessId, body);
        return Ok(result);
    }

    [HttpPost("check-duplicate")]
    public async Task<ActionResult<TradeDuplicateCheckResponse>> CheckDuplicate(Guid businessId, [FromBody] TradeDuplicateCheckRequest body)
    {
        var result = await _tradeService.CheckDuplicateAsync(businessId, body);
        return Ok(result);
    }

    // ─── Next Human ID ────────────────────────────────────────

    [HttpGet("next-human-id")]
    public async Task<ActionResult<NextHumanIdOut>> NextHumanId(Guid businessId)
    {
        var result = await _tradeService.GetNextHumanIdAsync(businessId);
        return Ok(result);
    }

    // ─── List ─────────────────────────────────────────────────

    [HttpGet("")]
    public async Task<ActionResult<TradePurchaseListOut>> ListPurchases(
        Guid businessId,
        [FromQuery] int limit = 20, [FromQuery] int offset = 0,
        [FromQuery] string? status = null, [FromQuery] string? q = null,
        [FromQuery] Guid? supplierId = null, [FromQuery] Guid? brokerId = null,
        [FromQuery] Guid? catalogItemId = null,
        [FromQuery] DateOnly? purchaseFrom = null, [FromQuery] DateOnly? purchaseTo = null,
        [FromQuery] bool includeLines = false)
    {
        limit = Math.Clamp(limit, 1, 50);
        offset = Math.Clamp(offset, 0, 10000);
        var result = await _tradeService.ListPurchasesAsync(businessId, limit, offset, status, q,
            supplierId, brokerId, catalogItemId, purchaseFrom, purchaseTo, includeLines, GetRole());
        return Ok(result);
    }

    // ─── Last Defaults ────────────────────────────────────────

    [HttpGet("last-defaults")]
    public async Task<ActionResult<TradeLastDefaultsOut>> LastDefaults(
        Guid businessId,
        [FromQuery] Guid catalogItemId,
        [FromQuery] Guid? supplierId = null, [FromQuery] Guid? brokerId = null)
    {
        var result = await _tradeService.GetLastDefaultsAsync(businessId, catalogItemId, supplierId, brokerId);
        return Ok(result);
    }

    // ─── Create ───────────────────────────────────────────────

    [HttpPost("")]
    public async Task<ActionResult<TradePurchaseOut>> CreatePurchase(Guid businessId,
        [FromBody] TradePurchaseCreateIn body,
        [FromHeader(Name = "Idempotency-Key")] string? idempotencyKey = null)
    {
        try
        {
            var result = await _tradeService.CreatePurchaseAsync(businessId, GetUserId(), body, idempotencyKey);
            return CreatedAtAction(nameof(GetPurchase), new { businessId, purchaseId = result.Id }, result);
        }
        catch (InvalidOperationException ex)
        {
            return UnprocessableEntity(new { detail = ex.Message });
        }
    }

    // ─── Get ──────────────────────────────────────────────────

    [HttpGet("{purchaseId:guid}")]
    public async Task<ActionResult<TradePurchaseOut>> GetPurchase(Guid businessId, Guid purchaseId)
    {
        var result = await _tradeService.GetPurchaseAsync(businessId, purchaseId);
        if (result is null) return NotFound(new { detail = "Purchase not found" });
        return Ok(result);
    }

    // ─── Update ───────────────────────────────────────────────

    [HttpPut("{purchaseId:guid}")]
    public async Task<ActionResult<TradePurchaseOut>> UpdatePurchase(Guid businessId, Guid purchaseId,
        [FromBody] TradePurchaseUpdateIn body)
    {
        try
        {
            var result = await _tradeService.UpdatePurchaseAsync(businessId, purchaseId, body);
            return Ok(result);
        }
        catch (KeyNotFoundException)
        {
            return NotFound(new { detail = "Purchase not found" });
        }
        catch (InvalidOperationException ex)
        {
            return Conflict(new { detail = ex.Message });
        }
    }

    // ─── Delete ───────────────────────────────────────────────

    [HttpDelete("{purchaseId:guid}")]
    public async Task<ActionResult> DeletePurchase(Guid businessId, Guid purchaseId)
    {
        var ok = await _tradeService.DeletePurchaseAsync(businessId, purchaseId);
        if (!ok) return NotFound(new { detail = "Purchase not found" });
        return NoContent();
    }

    // ─── Payment ──────────────────────────────────────────────

    [HttpPatch("{purchaseId:guid}/payment")]
    public async Task<ActionResult<TradePurchaseOut>> PatchPayment(Guid businessId, Guid purchaseId,
        [FromBody] PaymentUpdateIn body)
    {
        try
        {
            var result = await _tradeService.UpdatePaymentAsync(businessId, purchaseId, body);
            if (result is null) return NotFound(new { detail = "Purchase not found" });
            return Ok(result);
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(new { detail = ex.Message });
        }
    }

    [HttpPost("{purchaseId:guid}/mark-paid")]
    public async Task<ActionResult<TradePurchaseOut>> MarkPaid(Guid businessId, Guid purchaseId,
        [FromBody] MarkPaidIn body)
    {
        try
        {
            var result = await _tradeService.MarkPaidAsync(businessId, purchaseId, body);
            if (result is null) return NotFound(new { detail = "Purchase not found" });
            return Ok(result);
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(new { detail = ex.Message });
        }
    }

    [HttpPost("{purchaseId:guid}/cancel")]
    public async Task<ActionResult<TradePurchaseOut>> CancelPurchase(Guid businessId, Guid purchaseId)
    {
        var result = await _tradeService.CancelPurchaseAsync(businessId, purchaseId);
        if (result is null) return NotFound(new { detail = "Purchase not found" });
        return Ok(result);
    }

    // ─── Delivery Pipeline ────────────────────────────────────

    [HttpGet("delivery-pipeline")]
    public async Task<ActionResult<DeliveryPipelineCountsOut>> GetDeliveryPipeline(Guid businessId)
    {
        var result = await _tradeService.GetDeliveryPipelineAsync(businessId);
        return Ok(result);
    }

    // ─── Delivery Actions ─────────────────────────────────────

    [HttpPatch("{purchaseId:guid}/delivery")]
    public async Task<ActionResult<TradePurchaseOut>> PatchDelivery(Guid businessId, Guid purchaseId,
        [FromBody] DeliveryUpdateIn body)
    {
        try
        {
            var result = await _tradeService.PatchDeliveryAsync(businessId, purchaseId, body);
            if (result is null) return NotFound(new { detail = "Purchase not found" });
            return Ok(result);
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(new { detail = ex.Message });
        }
    }

    [HttpPost("{purchaseId:guid}/dispatch")]
    public async Task<ActionResult<TradePurchaseOut>> Dispatch(Guid businessId, Guid purchaseId,
        [FromBody] DeliveryDispatchIn body)
    {
        try
        {
            var result = await _tradeService.DispatchAsync(businessId, purchaseId, body, GetUserId(), GetUserName());
            if (result is null) return NotFound(new { detail = "Purchase not found" });
            return Ok(result);
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(new { detail = ex.Message });
        }
    }

    [HttpPost("{purchaseId:guid}/arrive")]
    public async Task<ActionResult<TradePurchaseOut>> Arrive(Guid businessId, Guid purchaseId,
        [FromBody] DeliveryArriveIn body)
    {
        try
        {
            var result = await _tradeService.ArriveAsync(businessId, purchaseId, body, GetUserId(), GetUserName());
            if (result is null) return NotFound(new { detail = "Purchase not found" });
            return Ok(result);
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(new { detail = ex.Message });
        }
    }

    [HttpPost("{purchaseId:guid}/commit-stock")]
    public async Task<ActionResult<TradePurchaseOut>> CommitStock(Guid businessId, Guid purchaseId)
    {
        try
        {
            var result = await _tradeService.CommitStockAsync(businessId, purchaseId, GetUserId(), GetUserName());
            if (result is null) return NotFound(new { detail = "Purchase not found" });
            return Ok(result);
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(new { detail = ex.Message });
        }
    }

    [HttpPost("{purchaseId:guid}/auto-commit")]
    public async Task<ActionResult<TradePurchaseOut>> AutoCommit(Guid businessId, Guid purchaseId)
    {
        var result = await _tradeService.AutoCommitAsync(businessId, purchaseId, GetUserId(), GetUserName());
        if (result is null)
            return BadRequest(new { detail = "Auto-commit not available — verify delivery and complete unit setup first." });
        return Ok(result);
    }

    [HttpPost("{purchaseId:guid}/verify")]
    public async Task<ActionResult<TradePurchaseOut>> VerifyDelivery(Guid businessId, Guid purchaseId,
        [FromBody] DeliveryVerifyIn body)
    {
        try
        {
            var result = await _tradeService.VerifyDeliveryAsync(businessId, purchaseId, body, GetUserId(), GetUserName());
            if (result is null) return NotFound(new { detail = "Purchase not found" });
            return Ok(result);
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(new { detail = ex.Message });
        }
    }

    // ─── Lifecycle Events ─────────────────────────────────────

    [HttpGet("{purchaseId:guid}/lifecycle-events")]
    public async Task<ActionResult<List<PurchaseLifecycleEventOut>>> ListLifecycleEvents(Guid businessId, Guid purchaseId)
    {
        var result = await _tradeService.ListLifecycleEventsAsync(businessId, purchaseId);
        return Ok(result);
    }

    [HttpPost("{purchaseId:guid}/lifecycle")]
    public async Task<ActionResult<TradePurchaseOut>> TransitionLifecycle(Guid businessId, Guid purchaseId,
        [FromBody] LifecycleEventCreateIn body)
    {
        try
        {
            var result = await _tradeService.TransitionLifecycleAsync(businessId, purchaseId, body.ToStatus, GetUserId(), body.Notes);
            if (result is null) return NotFound(new { detail = "Purchase not found" });
            return Ok(result);
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(new { detail = ex.Message });
        }
    }
}
