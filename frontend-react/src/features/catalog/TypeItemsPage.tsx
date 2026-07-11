import { useParams, useNavigate } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { LuArrowLeft, LuPlus, LuTriangle, LuPackage, LuPencil, LuTrash2, LuBarcode, LuHash } from "react-icons/lu";
import { useAuthStore } from "../../lib/stores/auth-store";
import { listCatalogItems, deleteCatalogItem, type CatalogItem } from "../../lib/api/catalog";
import { AppBar, Card, ListSkeleton, Button } from "../../components/ui";

export default function TypeItemsPage() {
  const { categoryId, typeId } = useParams<{ categoryId: string; typeId: string }>();
  const navigate = useNavigate();
  const businessId = useAuthStore((s) => s.businessId);

  const { data, isLoading, isError, error: fetchErr, refetch } = useQuery({
    queryKey: ["catalog", "items", businessId, typeId],
    queryFn: () => listCatalogItems(businessId!, { typeId }),
    enabled: !!businessId && !!typeId,
  });

  const handleDelete = async (item: CatalogItem) => {
    if (!window.confirm(`Delete "${item.name}"?`)) return;
    try {
      await deleteCatalogItem(businessId!, item.id);
      refetch();
    } catch (err: any) { alert(err?.response?.data?.detail || "Failed to delete"); }
  };

  return (
    <div className="flex flex-col min-h-full">
      <AppBar
        title="Items"
        leading={
          <button onClick={() => navigate(-1)} className="p-1.5 -ml-1.5 rounded-xl hover:bg-black/5"><LuArrowLeft size={22} /></button>
        }
        actions={[
          <button
            key="add"
            onClick={() => navigate(`/catalog/category/${categoryId}/type/${typeId}/add-item`)}
            className="flex items-center gap-1.5 h-9 px-3 rounded-xl bg-brand-accent text-white text-[13px] font-bold shadow-[0_4px_12px_rgba(21,154,138,0.30)] hover:shadow-[0_6px_16px_rgba(21,154,138,0.40)] active:scale-[0.97] transition-all"
          >
            <LuPlus size={16} />
            <span className="hidden sm:inline">Add Item</span>
          </button>,
        ]}
      />

      <div className="flex-1 px-4 pb-4">
        {isLoading ? <ListSkeleton rows={8} rowHeight={80} /> : isError ? (
          <div className="flex flex-col items-center justify-center py-16 gap-4">
            <LuTriangle size={48} className="text-loss" />
            <p className="text-text-muted text-sm">{(fetchErr as any)?.message || "Failed to load"}</p>
            <Button variant="secondary" onClick={() => refetch()}>Retry</Button>
          </div>
        ) : !data || data.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 gap-4">
            <LuPackage size={48} className="text-text-muted/40" />
            <p className="text-text-muted font-semibold">No items in this type</p>
          </div>
        ) : (
          <div className="flex flex-col gap-2">
            {data.map((item) => (
              <Card key={item.id} padding="sm" className="flex items-center gap-3">
                <div
                  className="flex-1 min-w-0 cursor-pointer"
                  onClick={() => navigate(`/catalog/item/${item.id}`)}
                >
                  <p className="text-[14px] font-bold text-text-primary truncate">{item.name}</p>
                  <div className="flex items-center gap-3 mt-0.5">
                    {item.itemCode && (
                      <span className="flex items-center gap-1 text-[11px] font-semibold text-text-muted">
                        <LuHash size={11} /> {item.itemCode}
                      </span>
                    )}
                    {item.barcode && (
                      <span className="flex items-center gap-1 text-[11px] font-semibold text-text-muted">
                        <LuBarcode size={11} /> {item.barcode}
                      </span>
                    )}
                    <span className="text-[11px] font-semibold text-text-muted">{item.defaultUnit || "—"}</span>
                  </div>
                </div>
                <button onClick={() => navigate(`/catalog/item/${item.id}/edit`)} className="p-1.5 rounded-xl hover:bg-brand-accent/10 text-text-muted">
                  <LuPencil size={15} />
                </button>
                <button onClick={() => handleDelete(item)} className="p-1.5 rounded-xl hover:bg-loss/10 text-loss/60">
                  <LuTrash2 size={15} />
                </button>
              </Card>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
