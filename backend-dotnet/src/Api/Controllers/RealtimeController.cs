using Microsoft.AspNetCore.Mvc;

namespace PurchaseAssistant.Api.Controllers;

[ApiController]
[Route("v1/businesses/{businessId:guid}/realtime")]
public class RealtimeController : ControllerBase
{
    [HttpGet("events")]
    public IActionResult Events(Guid businessId) => StatusCode(501);
}
