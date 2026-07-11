using Microsoft.AspNetCore.Mvc;

namespace PurchaseAssistant.Api.Controllers;

[ApiController]
[Route("v1/public/items")]
public class PublicItemsController : ControllerBase
{
    [HttpGet("{publicToken}")]
    public IActionResult GetByPublicToken(string publicToken) => StatusCode(501);
}
