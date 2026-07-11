namespace PurchaseAssistant.Application.Interfaces;

public interface IContactService
{
    // Suppliers
    Task ListSuppliersAsync();
    Task CreateSupplierAsync();
    Task GetSupplierAsync();
    Task UpdateSupplierAsync();
    Task DeleteSupplierAsync();
    Task GetSupplierMetricsAsync();

    // Brokers
    Task ListBrokersAsync();
    Task CreateBrokerAsync();
    Task GetBrokerAsync();
    Task UpdateBrokerAsync();
    Task DeleteBrokerAsync();
    Task GetBrokerMetricsAsync();
    Task GetLinkedSuppliersAsync();

    // Search
    Task SearchContactsAsync();
    Task GetCategoryItemsAsync();
}
