using Microsoft.AspNetCore.Mvc;

namespace PurchaseAssistant.Api.Controllers;

[ApiController]
[Route("v1/businesses/{businessId:guid}/media")]
public class MediaController : ControllerBase
{
    [HttpPost("ocr")]
    public IActionResult Ocr(Guid businessId) => StatusCode(501);
}
