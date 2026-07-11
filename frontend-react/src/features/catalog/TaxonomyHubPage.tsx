import { useNavigate } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { LuArrowLeft, LuFolder, LuChevronRight, LuListTree } from "react-icons/lu";
import { useAuthStore } from "../../lib/stores/auth-store";
import { getCategoryTypesIndex } from "../../lib/api/catalog";
import { AppBar, ListSkeleton, Button } from "../../components/ui";

export default function TaxonomyHubPage() {
  const navigate = useNavigate();
  const businessId = useAuthStore((s) => s.businessId);

  const { data, isLoading } = useQuery({
    queryKey: ["catalog", "taxonomy-index", businessId],
    queryFn: () => getCategoryTypesIndex(businessId!),
    enabled: !!businessId,
  });

  const grouped = data?.reduce<Record<string, { id: string; name: string }[]>>((acc, t) => {
    const key = t.categoryName;
    if (!acc[key]) acc[key] = [];
    acc[key].push({ id: t.id, name: t.name });
    return acc;
  }, {});

  return (
    <div className="flex flex-col min-h-full">
      <AppBar title="Taxonomy" leading={<button onClick={() => navigate(-1)} className="p-1.5 -ml-1.5 rounded-xl hover:bg-black/5"><LuArrowLeft size={22} /></button>} />
      <div className="flex-1 px-4 pb-6 space-y-2 overflow-y-auto">
        {isLoading && <ListSkeleton rows={6} />}
        {grouped && Object.entries(grouped).map(([category, types]) => (
          <div key={category} className="rounded-xl border border-card-border overflow-hidden">
            <div className="px-4 py-3 bg-card-bg flex items-center gap-2">
              <LuFolder size={16} className="text-brand-accent shrink-0" />
              <span className="text-[14px] font-bold text-text-primary">{category}</span>
              <span className="text-[11px] font-medium text-text-muted ml-auto">{types.length} type{types.length !== 1 ? "s" : ""}</span>
            </div>
            {types.map((t) => (
              <button
                key={t.id}
                onClick={() => navigate(`/catalog/category/${t.id.split("/")[0]}/type/${t.id}`)}
                className="flex items-center gap-2 w-full px-4 py-2.5 border-t border-card-border hover:bg-card-bg text-left"
              >
                <LuListTree size={14} className="text-text-muted shrink-0" />
                <span className="text-[13px] font-medium text-text-primary">{t.name}</span>
                <LuChevronRight size={14} className="text-text-muted ml-auto" />
              </button>
            ))}
          </div>
        ))}
        {grouped && Object.keys(grouped).length === 0 && (
          <div className="flex flex-col items-center justify-center py-16 gap-3">
            <LuListTree size={48} className="text-text-muted/40" />
            <p className="text-text-muted text-sm">No categories yet</p>
            <Button variant="secondary" onClick={() => navigate("/catalog/new-category")}>Create first category</Button>
          </div>
        )}
      </div>
    </div>
  );
}
