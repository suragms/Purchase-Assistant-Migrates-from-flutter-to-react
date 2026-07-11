using Microsoft.AspNetCore.Mvc;

namespace PurchaseAssistant.Api.Controllers;

[ApiController]
[Route("v1/businesses/{businessId:guid}/search")]
public class SearchController : ControllerBase
{
    [HttpGet]
    public IActionResult Search(Guid businessId) => StatusCode(501);
}
