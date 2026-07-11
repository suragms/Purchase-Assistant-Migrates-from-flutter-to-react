using Microsoft.AspNetCore.Mvc;

namespace PurchaseAssistant.Api.Controllers;

[ApiController]
[Route("v1/businesses/{businessId:guid}/exports")]
public class ExportsController : ControllerBase
{
    [HttpPost("backup")]
    public IActionResult Backup(Guid businessId) => StatusCode(501);

    [HttpGet("stock-inventory.xlsx")]
    public IActionResult GetStockInventory(Guid businessId) => StatusCode(501);

    [HttpGet("purchases-month.pdf")]
    public IActionResult GetPurchasesMonthPdf(Guid businessId) => StatusCode(501);

    [HttpGet("backup/export")]
    public IActionResult ExportBackup(Guid businessId) => StatusCode(501);
}
