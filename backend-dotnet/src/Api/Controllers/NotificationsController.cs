using Microsoft.AspNetCore.Mvc;

namespace PurchaseAssistant.Api.Controllers;

[ApiController]
[Route("v1/businesses/{businessId:guid}/notifications")]
public class NotificationsController : ControllerBase
{
    [HttpGet]
    public IActionResult List(Guid businessId) => StatusCode(501);

    [HttpGet("summary")]
    public IActionResult GetSummary(Guid businessId) => StatusCode(501);

    [HttpGet("unread-count")]
    public IActionResult GetUnreadCount(Guid businessId) => StatusCode(501);

    [HttpPatch("{notificationId:guid}")]
    public IActionResult MarkRead(Guid businessId, Guid notificationId) => StatusCode(501);

    [HttpPost("mark-all-read")]
    public IActionResult MarkAllRead(Guid businessId) => StatusCode(501);

    [HttpDelete("clear-all")]
    public IActionResult ClearAll(Guid businessId) => StatusCode(501);

    [HttpPost("client-event")]
    public IActionResult CreateClientEvent(Guid businessId) => StatusCode(501);
}
