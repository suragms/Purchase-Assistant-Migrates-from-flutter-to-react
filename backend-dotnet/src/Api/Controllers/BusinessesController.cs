using Microsoft.AspNetCore.Mvc;
using PurchaseAssistant.Application.DTOs;

namespace PurchaseAssistant.Api.Controllers;

[ApiController]
[Route("v1/businesses")]
public class BusinessesController : ControllerBase
{
    [HttpGet("{id:guid}")]
    public Task<ActionResult> GetById(Guid id) => Task.FromResult<ActionResult>(StatusCode(501));

    [HttpPost]
    public Task<ActionResult> Create([FromBody] CreateBusinessRequest request) => Task.FromResult<ActionResult>(StatusCode(501));

    [HttpPut("{id:guid}")]
    public Task<ActionResult> Update(Guid id, [FromBody] UpdateBusinessRequest request) => Task.FromResult<ActionResult>(StatusCode(501));

    [HttpDelete("{id:guid}")]
    public Task<ActionResult> Delete(Guid id) => Task.FromResult<ActionResult>(StatusCode(501));
}
