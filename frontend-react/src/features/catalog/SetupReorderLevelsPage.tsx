import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { LuArrowLeft, LuSave } from "react-icons/lu";
import { useAuthStore } from "../../lib/stores/auth-store";
import { listCatalogItems, bulkReorderCatalogItems } from "../../lib/api/catalog";
import { AppBar, Input, Button, ListSkeleton } from "../../components/ui";

export default function SetupReorderLevelsPage() {
  const navigate = useNavigate();
  const businessId = useAuthStore((s) => s.businessId);

  const { data: items, isLoading, refetch } = useQuery({
    queryKey: ["catalog", "all-items", businessId],
    queryFn: () => listCatalogItems(businessId!, { fetchAllPages: true }),
    enabled: !!businessId,
  });

  const [levels, setLevels] = useState<Record<string, string>>({});
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleSaveAll = async () => {
    const entries = Object.entries(levels).filter(([, v]) => v !== "" && v !== "0");
    if (entries.length === 0) return;
    setSaving(true); setError(null);
    try {
      for (const [itemId, level] of entries) {
        await bulkReorderCatalogItems(businessId!, [itemId], parseFloat(level));
      }
      setLevels({});
      refetch();
    } catch (err: any) { setError(err?.response?.data?.detail || "Failed to save"); }
    finally { setSaving(false); }
  };

  return (
    <div className="flex flex-col min-h-full">
      <AppBar title="Reorder Levels" leading={<button onClick={() => navigate(-1)} className="p-1.5 -ml-1.5 rounded-xl hover:bg-black/5"><LuArrowLeft size={22} /></button>} />
      <div className="flex-1 px-4 pb-6 space-y-3 overflow-y-auto">
        {isLoading && <ListSkeleton rows={6} />}

        {error && <p className="text-loss text-[13px] font-medium">{error}</p>}

        {items?.map((item) => (
          <div key={item.id} className="rounded-xl border border-card-border p-4">
            <button onClick={() => navigate(`/catalog/item/${item.id}`)} className="text-[14px] font-bold text-text-primary hover:underline text-left">{item.name}</button>
            <div className="flex gap-2 mt-2 items-center">
              <Input
                label="Reorder level"
                type="number"
                step="any"
                value={levels[item.id] ?? ""}
                onChange={(e) => setLevels((p) => ({ ...p, [item.id]: e.target.value }))}
              />
            </div>
          </div>
        ))}

        {items && (
          <Button onClick={handleSaveAll} loading={saving} disabled={Object.keys(levels).length === 0}>
            <LuSave size={16} /> Save All
          </Button>
        )}
      </div>
    </div>
  );
}
