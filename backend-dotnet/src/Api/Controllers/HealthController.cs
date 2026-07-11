using Microsoft.AspNetCore.Mvc;

namespace PurchaseAssistant.Api.Controllers;

[ApiController]
public class HealthController : ControllerBase
{
    [HttpGet("/health")]
    public IActionResult GetRoot() => StatusCode(501);

    [HttpHead("/health")]
    public IActionResult HeadRoot() => StatusCode(501);

    [HttpGet("/health/live")]
    public IActionResult GetLive() => StatusCode(501);

    [HttpGet("/health/ready")]
    public IActionResult GetReady() => StatusCode(501);

    [HttpGet("/health/db-check")]
    public IActionResult GetDbCheck() => StatusCode(501);
}
