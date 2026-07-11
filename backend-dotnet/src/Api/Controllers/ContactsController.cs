using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using PurchaseAssistant.Domain.Entities.Contacts;
using PurchaseAssistant.Infrastructure.Data;

namespace PurchaseAssistant.Api.Controllers;

[ApiController]
[Authorize]
[Route("v1/businesses/{businessId:guid}")]
public class ContactsController : ControllerBase
{
    private readonly PurchaseAssistantDbContext _db;

    public ContactsController(PurchaseAssistantDbContext db)
    {
        _db = db;
    }

    // ---- Suppliers ----
    [HttpGet("suppliers")]
    public async Task<IActionResult> ListSuppliers(Guid businessId)
    {
        var rows = await _db.Suppliers
            .Where(s => s.BusinessId == businessId)
            .OrderBy(s => s.Name)
            .Select(s => new SupplierDto(
                s.Id,
                s.Name,
                s.Phone,
                s.Location,
                s.GstNumber,
                s.Address,
                s.DefaultDiscount,
                s.DefaultDeliveredRate,
                s.DefaultBilltyRate,
                s.FreightType))
            .ToListAsync();
        return Ok(rows);
    }

    [HttpPost("suppliers")]
    public async Task<IActionResult> CreateSupplier(Guid businessId, [FromBody] ContactCreateRequest body)
    {
        if (string.IsNullOrWhiteSpace(body.Name))
            return BadRequest(new { detail = "Supplier name is required" });

        var row = new Supplier
        {
            BusinessId = businessId,
            Name = body.Name.Trim(),
            Phone = Clean(body.Phone),
            Location = Clean(body.Location),
            GstNumber = Clean(body.GstNumber),
            Address = Clean(body.Address),
            Notes = Clean(body.Notes),
            DefaultPaymentDays = body.DefaultPaymentDays,
            DefaultDiscount = body.DefaultDiscount,
            DefaultDeliveredRate = body.DefaultDeliveredRate,
            DefaultBilltyRate = body.DefaultBilltyRate,
            FreightType = Clean(body.FreightType),
        };
        _db.Suppliers.Add(row);
        await _db.SaveChangesAsync();

        return StatusCode(201, new SupplierDto(
            row.Id, row.Name, row.Phone, row.Location, row.GstNumber, row.Address,
            row.DefaultDiscount, row.DefaultDeliveredRate, row.DefaultBilltyRate, row.FreightType));
    }

    [HttpGet("suppliers/{supplierId:guid}")]
    public async Task<IActionResult> GetSupplier(Guid businessId, Guid supplierId)
    {
        var row = await _db.Suppliers.FirstOrDefaultAsync(s => s.BusinessId == businessId && s.Id == supplierId);
        if (row == null) return NotFound(new { detail = "Supplier not found" });
        return Ok(new SupplierDto(
            row.Id, row.Name, row.Phone, row.Location, row.GstNumber, row.Address,
            row.DefaultDiscount, row.DefaultDeliveredRate, row.DefaultBilltyRate, row.FreightType));
    }

    [HttpPatch("suppliers/{supplierId:guid}")]
    public async Task<IActionResult> UpdateSupplier(Guid businessId, Guid supplierId, [FromBody] ContactCreateRequest body)
    {
        var row = await _db.Suppliers.FirstOrDefaultAsync(s => s.BusinessId == businessId && s.Id == supplierId);
        if (row == null) return NotFound(new { detail = "Supplier not found" });
        if (!string.IsNullOrWhiteSpace(body.Name)) row.Name = body.Name.Trim();
        if (body.Phone != null) row.Phone = Clean(body.Phone);
        if (body.Location != null) row.Location = Clean(body.Location);
        if (body.GstNumber != null) row.GstNumber = Clean(body.GstNumber);
        if (body.Address != null) row.Address = Clean(body.Address);
        if (body.Notes != null) row.Notes = Clean(body.Notes);
        if (body.DefaultPaymentDays.HasValue) row.DefaultPaymentDays = body.DefaultPaymentDays;
        if (body.DefaultDiscount.HasValue) row.DefaultDiscount = body.DefaultDiscount;
        if (body.DefaultDeliveredRate.HasValue) row.DefaultDeliveredRate = body.DefaultDeliveredRate;
        if (body.DefaultBilltyRate.HasValue) row.DefaultBilltyRate = body.DefaultBilltyRate;
        if (body.FreightType != null) row.FreightType = Clean(body.FreightType);
        await _db.SaveChangesAsync();
        return Ok(new SupplierDto(
            row.Id, row.Name, row.Phone, row.Location, row.GstNumber, row.Address,
            row.DefaultDiscount, row.DefaultDeliveredRate, row.DefaultBilltyRate, row.FreightType));
    }

    [HttpDelete("suppliers/{supplierId:guid}")]
    public async Task<IActionResult> DeleteSupplier(Guid businessId, Guid supplierId)
    {
        var row = await _db.Suppliers.FirstOrDefaultAsync(s => s.BusinessId == businessId && s.Id == supplierId);
        if (row == null) return NotFound(new { detail = "Supplier not found" });
        _db.Suppliers.Remove(row);
        await _db.SaveChangesAsync();
        return NoContent();
    }

    [HttpGet("suppliers/{supplierId:guid}/metrics")]
    public IActionResult GetSupplierMetrics(Guid businessId, Guid supplierId) => StatusCode(501);

    // ---- Brokers ----
    [HttpGet("brokers")]
    public async Task<IActionResult> ListBrokers(Guid businessId)
    {
        var rows = await _db.Brokers
            .Where(b => b.BusinessId == businessId)
            .OrderBy(b => b.Name)
            .Select(b => new BrokerDto(
                b.Id, b.Name, b.Phone, b.Location, b.CommissionType, b.CommissionValue))
            .ToListAsync();
        return Ok(rows);
    }

    [HttpPost("brokers")]
    public async Task<IActionResult> CreateBroker(Guid businessId, [FromBody] ContactCreateRequest body)
    {
        if (string.IsNullOrWhiteSpace(body.Name))
            return BadRequest(new { detail = "Broker name is required" });
        var row = new Broker
        {
            BusinessId = businessId,
            Name = body.Name.Trim(),
            Phone = Clean(body.Phone),
            Location = Clean(body.Location),
            Notes = Clean(body.Notes),
            CommissionType = Clean(body.CommissionType) ?? "percent",
            CommissionValue = body.CommissionValue,
            DefaultPaymentDays = body.DefaultPaymentDays,
            DefaultDiscount = body.DefaultDiscount,
            DefaultDeliveredRate = body.DefaultDeliveredRate,
            DefaultBilltyRate = body.DefaultBilltyRate,
            FreightType = Clean(body.FreightType),
        };
        _db.Brokers.Add(row);
        await _db.SaveChangesAsync();
        return StatusCode(201, new BrokerDto(row.Id, row.Name, row.Phone, row.Location, row.CommissionType, row.CommissionValue));
    }

    [HttpGet("brokers/{brokerId:guid}")]
    public async Task<IActionResult> GetBroker(Guid businessId, Guid brokerId)
    {
        var row = await _db.Brokers.FirstOrDefaultAsync(b => b.BusinessId == businessId && b.Id == brokerId);
        if (row == null) return NotFound(new { detail = "Broker not found" });
        return Ok(new BrokerDto(row.Id, row.Name, row.Phone, row.Location, row.CommissionType, row.CommissionValue));
    }

    [HttpPatch("brokers/{brokerId:guid}")]
    public async Task<IActionResult> UpdateBroker(Guid businessId, Guid brokerId, [FromBody] ContactCreateRequest body)
    {
        var row = await _db.Brokers.FirstOrDefaultAsync(b => b.BusinessId == businessId && b.Id == brokerId);
        if (row == null) return NotFound(new { detail = "Broker not found" });
        if (!string.IsNullOrWhiteSpace(body.Name)) row.Name = body.Name.Trim();
        if (body.Phone != null) row.Phone = Clean(body.Phone);
        if (body.Location != null) row.Location = Clean(body.Location);
        if (body.Notes != null) row.Notes = Clean(body.Notes);
        if (body.CommissionType != null) row.CommissionType = Clean(body.CommissionType);
        if (body.CommissionValue.HasValue) row.CommissionValue = body.CommissionValue;
        await _db.SaveChangesAsync();
        return Ok(new BrokerDto(row.Id, row.Name, row.Phone, row.Location, row.CommissionType, row.CommissionValue));
    }

    [HttpDelete("brokers/{brokerId:guid}")]
    public async Task<IActionResult> DeleteBroker(Guid businessId, Guid brokerId)
    {
        var row = await _db.Brokers.FirstOrDefaultAsync(b => b.BusinessId == businessId && b.Id == brokerId);
        if (row == null) return NotFound(new { detail = "Broker not found" });
        _db.Brokers.Remove(row);
        await _db.SaveChangesAsync();
        return NoContent();
    }

    [HttpGet("brokers/{brokerId:guid}/metrics")]
    public IActionResult GetBrokerMetrics(Guid businessId, Guid brokerId) => StatusCode(501);

    [HttpGet("brokers/{brokerId:guid}/linked-suppliers")]
    public IActionResult GetLinkedSuppliers(Guid businessId, Guid brokerId) => StatusCode(501);

    // ---- Search ----
    [HttpGet("contacts/search")]
    public IActionResult SearchContacts(Guid businessId) => StatusCode(501);

    [HttpGet("contacts/category-items")]
    public IActionResult GetCategoryItems(Guid businessId) => StatusCode(501);

    private static string? Clean(string? value)
    {
        return string.IsNullOrWhiteSpace(value) ? null : value.Trim();
    }
}

public record ContactCreateRequest(
    string Name,
    string? Phone,
    string? Location,
    string? GstNumber,
    string? Address,
    string? Notes,
    int? DefaultPaymentDays,
    decimal? DefaultDiscount,
    decimal? DefaultDeliveredRate,
    decimal? DefaultBilltyRate,
    string? FreightType,
    string? CommissionType,
    decimal? CommissionValue);

public record SupplierDto(
    Guid Id,
    string Name,
    string? Phone,
    string? Location,
    string? GstNumber,
    string? Address,
    decimal? DefaultDiscount,
    decimal? DefaultDeliveredRate,
    decimal? DefaultBilltyRate,
    string? FreightType);

public record BrokerDto(
    Guid Id,
    string Name,
    string? Phone,
    string? Location,
    string? CommissionType,
    decimal? CommissionValue);
