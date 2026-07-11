using Microsoft.AspNetCore.Mvc;

namespace PurchaseAssistant.Api.Controllers;

[ApiController]
[Route("v1/businesses/{businessId:guid}/stock-audits")]
public class StockAuditsController : ControllerBase
{
    [HttpGet]
    public IActionResult List(Guid businessId) => StatusCode(501);

    [HttpPost]
    public IActionResult Create(Guid businessId) => StatusCode(501);

    [HttpGet("{auditId:guid}")]
    public IActionResult Get(Guid businessId, Guid auditId) => StatusCode(501);

    [HttpPatch("{auditId:guid}")]
    public IActionResult Update(Guid businessId, Guid auditId) => StatusCode(501);

    [HttpPost("{auditId:guid}/items")]
    public IActionResult AddItem(Guid businessId, Guid auditId) => StatusCode(501);

    [HttpPost("{auditId:guid}/complete")]
    public IActionResult Complete(Guid businessId, Guid auditId) => StatusCode(501);

    [HttpPost("{auditId:guid}/resolve-discrepancies")]
    public IActionResult ResolveDiscrepancies(Guid businessId, Guid auditId) => StatusCode(501);
}
