using Microsoft.AspNetCore.Mvc;

namespace PurchaseAssistant.Api.Controllers;

[ApiController]
[Route("v1/businesses/{businessId:guid}/dashboard")]
public class DashboardController : ControllerBase
{
    [HttpGet]
    public IActionResult GetDashboard(Guid businessId) => StatusCode(501);
}
