namespace PurchaseAssistant.Application.Interfaces;

public interface ITradePurchaseService
{
    // Draft
    Task GetDraftAsync();
    Task UpsertDraftAsync();
    Task DeleteDraftAsync();

    // Preview & Validation
    Task PreviewLinesAsync();
    Task ValidateAsync();
    Task CheckDuplicateAsync();

    // CRUD
    Task ListAsync();
    Task CreateAsync();
    Task GetAsync();
    Task UpdateAsync();
    Task DeleteAsync();
    Task GetNextHumanIdAsync();
    Task GetLastDefaultsAsync();

    // Delivery Pipeline
    Task GetDeliveryPipelineAsync();
    Task UpdateDeliveryAsync();
    Task DispatchAsync();
    Task ArriveAsync();
    Task CommitStockAsync();
    Task AutoCommitAsync();
    Task VerifyAsync();

    // Payment
    Task UpdatePaymentAsync();
    Task MarkPaidAsync();
    Task CancelAsync();

    // Lifecycle & Damage
    Task GetLifecycleEventsAsync();
    Task TransitionLifecycleAsync();
    Task CreateDamageReportAsync();
    Task ListDamageReportsAsync();
}
