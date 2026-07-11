namespace PurchaseAssistant.Application.Interfaces;

public interface ILegacyArchiveService
{
    Task<int> CountArchivedEntryLinesForVariantAsync(Guid variantId, CancellationToken ct = default);
    Task<int> CountArchivedEntryLinesForVariantsAsync(List<Guid> variantIds, CancellationToken ct = default);
}
