import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { LuArrowLeft, LuCopy, LuTrash2 } from "react-icons/lu";
import { useAuthStore } from "../../lib/stores/auth-store";
import { getCatalogDuplicateClusters, bulkArchiveCatalogItems } from "../../lib/api/catalog";
import { AppBar, ListSkeleton, Card } from "../../components/ui";

export default function DuplicatesPage() {
  const navigate = useNavigate();
  const businessId = useAuthStore((s) => s.businessId);

  const [selected, setSelected] = useState<Set<string>>(new Set());
  const { data, isLoading, refetch } = useQuery({
    queryKey: ["catalog", "duplicates", businessId],
    queryFn: () => getCatalogDuplicateClusters(businessId!, 0.6),
    enabled: !!businessId,
  });

  const handleArchive = async () => {
    if (selected.size === 0) return;
    try {
      await bulkArchiveCatalogItems(businessId!, Array.from(selected));
      setSelected(new Set());
      refetch();
    } catch { /* ignore */ }
  };

  const toggle = (id: string) => {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id); else next.add(id);
      return next;
    });
  };

  return (
    <div className="flex flex-col min-h-full">
      <AppBar
        title="Duplicates"
        leading={<button onClick={() => navigate(-1)} className="p-1.5 -ml-1.5 rounded-xl hover:bg-black/5"><LuArrowLeft size={22} /></button>}
        actions={selected.size > 0 ? [
          <button key="archive" onClick={handleArchive} className="flex items-center gap-1.5 h-9 px-3 rounded-xl bg-loss/10 text-loss text-[13px] font-bold hover:bg-loss/20">
            <LuTrash2 size={14} /> Archive ({selected.size})
          </button>,
        ] : undefined}
      />
      <div className="flex-1 px-4 pb-6 space-y-2 overflow-y-auto">
        {isLoading && <ListSkeleton rows={6} />}
        {data?.map((pair, i) => (
          <Card key={i} padding="md">
            <div className="flex items-center gap-1">
              <input type="checkbox" checked={selected.has(pair.idA)} onChange={() => toggle(pair.idA)} className="shrink-0" />
              <button onClick={() => navigate(`/catalog/item/${pair.idA}`)} className="flex-1 text-left text-[13px] font-bold text-text-primary hover:underline truncate">{pair.nameA}</button>
            </div>
            <div className="flex items-center gap-1 mt-1">
              <input type="checkbox" checked={selected.has(pair.idB)} onChange={() => toggle(pair.idB)} className="shrink-0" />
              <button onClick={() => navigate(`/catalog/item/${pair.idB}`)} className="flex-1 text-left text-[13px] font-bold text-text-primary hover:underline truncate">{pair.nameB}</button>
            </div>
            <p className="text-[11px] text-text-muted mt-1.5 font-medium">Match: {Math.round(pair.score * 100)}%</p>
          </Card>
        ))}
        {!isLoading && !data?.length && (
          <div className="flex flex-col items-center justify-center py-16 gap-3">
            <LuCopy size={48} className="text-text-muted/40" />
            <p className="text-text-muted text-sm">No duplicates found</p>
          </div>
        )}
      </div>
    </div>
  );
}
