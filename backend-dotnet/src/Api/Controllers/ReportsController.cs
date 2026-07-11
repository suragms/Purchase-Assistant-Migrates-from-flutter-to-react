using Microsoft.AspNetCore.Mvc;

namespace PurchaseAssistant.Api.Controllers;

[ApiController]
[Route("v1/businesses/{businessId:guid}/reports")]
public class ReportsController : ControllerBase
{
    [HttpGet("trade")]
    public IActionResult GetTradeReport(Guid businessId) => StatusCode(501);

    [HttpGet("saved-views")]
    public IActionResult ListSavedViews(Guid businessId) => StatusCode(501);

    [HttpPost("saved-views")]
    public IActionResult CreateSavedView(Guid businessId) => StatusCode(501);

    [HttpPatch("saved-views/{viewId:guid}")]
    public IActionResult UpdateSavedView(Guid businessId, Guid viewId) => StatusCode(501);

    [HttpDelete("saved-views/{viewId:guid}")]
    public IActionResult DeleteSavedView(Guid businessId, Guid viewId) => StatusCode(501);
}
