using Microsoft.EntityFrameworkCore;
using PurchaseAssistant.Application.Interfaces;
using PurchaseAssistant.Infrastructure.Data;

namespace PurchaseAssistant.Infrastructure.Services;

public class LegacyArchiveService : ILegacyArchiveService
{
    private readonly PurchaseAssistantDbContext _db;

    public LegacyArchiveService(PurchaseAssistantDbContext db)
    {
        _db = db;
    }

    public async Task<int> CountArchivedEntryLinesForVariantAsync(Guid variantId, CancellationToken ct = default)
    {
        var result = await CountArchivedEntryLinesForVariantsAsync([variantId], ct);
        return result;
    }

    public async Task<int> CountArchivedEntryLinesForVariantsAsync(List<Guid> variantIds, CancellationToken ct = default)
    {
        if (variantIds.Count == 0) return 0;

        try
        {
            var ids = variantIds.Select(v => v.ToString()).ToList();
            var raw = await _db.Database.SqlQueryRaw<int>(
                "SELECT count(*) FROM _archived_entry_line_items WHERE catalog_variant_id = ANY({0})",
                ids).FirstOrDefaultAsync(ct);
            return raw;
        }
        catch
        {
            return 0;
        }
    }
}
