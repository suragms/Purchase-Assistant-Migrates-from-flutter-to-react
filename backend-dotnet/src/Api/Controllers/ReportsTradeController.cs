using Microsoft.AspNetCore.Mvc;

namespace PurchaseAssistant.Api.Controllers;

[ApiController]
[Route("v1/businesses/{businessId:guid}/reports/trade")]
public class ReportsTradeController : ControllerBase
{
    [HttpGet("summary")]
    public Task<ActionResult> GetSummary(Guid businessId) => Task.FromResult<ActionResult>(StatusCode(501));

    [HttpGet("supplier-wise")]
    public Task<ActionResult> GetSupplierWise(Guid businessId) => Task.FromResult<ActionResult>(StatusCode(501));

    [HttpGet("item-wise")]
    public Task<ActionResult> GetItemWise(Guid businessId) => Task.FromResult<ActionResult>(StatusCode(501));
}
