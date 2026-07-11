using Microsoft.AspNetCore.Mvc;

namespace PurchaseAssistant.Api.Controllers;

[ApiController]
[Route("v1/businesses/{businessId:guid}/operations")]
public class OperationsController : ControllerBase
{
    [HttpGet("daily-usage")]
    public IActionResult GetDailyUsage(Guid businessId) => StatusCode(501);

    [HttpPost("daily-usage")]
    public IActionResult CreateDailyUsage(Guid businessId) => StatusCode(501);

    [HttpGet("checklists")]
    public IActionResult ListChecklists(Guid businessId) => StatusCode(501);

    [HttpPost("checklists/completions")]
    public IActionResult CreateChecklistCompletion(Guid businessId) => StatusCode(501);

    [HttpGet("checklists/completions")]
    public IActionResult ListChecklistCompletions(Guid businessId) => StatusCode(501);
}
