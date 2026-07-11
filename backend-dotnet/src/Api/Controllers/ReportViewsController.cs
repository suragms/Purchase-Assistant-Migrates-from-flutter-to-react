using Microsoft.AspNetCore.Mvc;

namespace PurchaseAssistant.Api.Controllers;

[ApiController]
[Route("v1/businesses/{businessId:guid}/report-views")]
public class ReportViewsController : ControllerBase
{
    [HttpGet]
    public Task<ActionResult> GetAll(Guid businessId) => Task.FromResult<ActionResult>(StatusCode(501));

    [HttpPost]
    public Task<ActionResult> Create(Guid businessId) => Task.FromResult<ActionResult>(StatusCode(501));

    [HttpDelete("{id:guid}")]
    public Task<ActionResult> Delete(Guid businessId, Guid id) => Task.FromResult<ActionResult>(StatusCode(501));
}
