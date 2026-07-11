using PurchaseAssistant.Application.DTOs;

namespace PurchaseAssistant.Application.Services;

public interface IContactService
{
    Task<IReadOnlyList<SupplierResponse>> GetSuppliersAsync(Guid businessId);
    Task<SupplierResponse> CreateSupplierAsync(Guid businessId, CreateSupplierRequest request);
    Task<IReadOnlyList<BrokerResponse>> GetBrokersAsync(Guid businessId);
    Task<BrokerResponse> CreateBrokerAsync(Guid businessId, CreateBrokerRequest request);
}
