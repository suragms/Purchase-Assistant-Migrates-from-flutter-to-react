using Microsoft.AspNetCore.Mvc;

namespace PurchaseAssistant.Api.Controllers;

[ApiController]
[Route("v1/businesses/{businessId:guid}")]
public abstract class BaseBusinessController : ControllerBase
{
    protected Guid GetBusinessId() => Guid.Parse(RouteData.Values["businessId"]!.ToString()!);
}
