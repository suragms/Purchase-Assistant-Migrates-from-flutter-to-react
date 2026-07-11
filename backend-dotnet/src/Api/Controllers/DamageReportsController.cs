using Microsoft.AspNetCore.Mvc;

namespace PurchaseAssistant.Api.Controllers;

[ApiController]
[Route("v1/businesses/{businessId:guid}/damage-reports")]
public class DamageReportsController : ControllerBase
{
    [HttpGet("pending-count")]
    public IActionResult GetPendingCount(Guid businessId) => StatusCode(501);

    [HttpPatch("{reportId:guid}")]
    public IActionResult UpdateReportStatus(Guid businessId, Guid reportId) => StatusCode(501);
}
