import { useState } from "react";
import { useParams, useNavigate } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { LuArrowLeft, LuPlus, LuTriangle, LuPencil, LuTrash2, LuFolder, LuPackage } from "react-icons/lu";
import { useAuthStore } from "../../lib/stores/auth-store";
import { listCategoryTypes, createCategoryType, updateCategoryType, deleteCategoryType } from "../../lib/api/catalog";
import { AppBar, Card, Input, ListSkeleton, Button } from "../../components/ui";

export default function CategoryDetailPage() {
  const { categoryId } = useParams<{ categoryId: string }>();
  const navigate = useNavigate();
  const businessId = useAuthStore((s) => s.businessId);

  const { data: types, isLoading, isError, error: fetchErr, refetch } = useQuery({
    queryKey: ["catalog", "types", businessId, categoryId],
    queryFn: () => listCategoryTypes(businessId!, categoryId!),
    enabled: !!businessId && !!categoryId,
  });

  const [showCreate, setShowCreate] = useState(false);
  const [newName, setNewName] = useState("");
  const [editId, setEditId] = useState<string | null>(null);
  const [editName, setEditName] = useState("");
  const [error, setError] = useState<string | null>(null);

  const handleCreate = async () => {
    if (!newName.trim()) return;
    setError(null);
    try {
      await createCategoryType(businessId!, categoryId!, newName.trim());
      setNewName(""); setShowCreate(false); refetch();
    } catch (err: any) { setError(err?.response?.data?.detail || "Failed to create"); }
  };

  const handleRename = async (typeId: string) => {
    if (!editName.trim()) return;
    setError(null);
    try {
      await updateCategoryType(businessId!, categoryId!, typeId, editName.trim());
      setEditId(null); setEditName(""); refetch();
    } catch (err: any) { setError(err?.response?.data?.detail || "Failed to rename"); }
  };

  const handleDelete = async (typeId: string, name: string) => {
    if (!window.confirm(`Delete type "${name}"? Items must be moved first.`)) return;
    setError(null);
    try {
      await deleteCategoryType(businessId!, categoryId!, typeId);
      refetch();
    } catch (err: any) { setError(err?.response?.data?.detail || "Failed to delete"); }
  };

  return (
    <div className="flex flex-col min-h-full">
      <AppBar
        title="Category"
        leading={
          <button onClick={() => navigate(-1)} className="p-1.5 -ml-1.5 rounded-xl hover:bg-black/5"><LuArrowLeft size={22} /></button>
        }
        actions={[
          <button
            key="add"
            onClick={() => setShowCreate(true)}
            className="flex items-center gap-1.5 h-9 px-3 rounded-xl bg-brand-accent text-white text-[13px] font-bold shadow-[0_4px_12px_rgba(21,154,138,0.30)] hover:shadow-[0_6px_16px_rgba(21,154,138,0.40)] active:scale-[0.97] transition-all"
          >
            <LuPlus size={16} />
            <span className="hidden sm:inline">Add Type</span>
          </button>,
        ]}
      />

      <div className="flex-1 px-4 pb-4">
        {isLoading ? (
          <ListSkeleton rows={6} rowHeight={64} />
        ) : isError ? (
          <div className="flex flex-col items-center justify-center py-16 gap-4">
            <LuTriangle size={48} className="text-loss" />
            <p className="text-text-muted text-sm">{(fetchErr as any)?.message || "Failed to load"}</p>
            <Button variant="secondary" onClick={() => refetch()}>Retry</Button>
          </div>
        ) : types && types.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 gap-4">
            <LuPackage size={48} className="text-text-muted/40" />
            <p className="text-text-muted font-semibold">No types yet</p>
            <p className="text-text-muted/60 text-sm">Create subcategories (types) to organize items</p>
          </div>
        ) : (
          <div className="flex flex-col gap-2">
            {types?.map((t) => (
              <Card key={t.id} padding="sm" className="flex items-center gap-3">
                <div className="p-2 rounded-xl bg-brand-accent/10 text-brand-accent shrink-0">
                  <LuFolder size={20} />
                </div>
                <div
                  className="flex-1 min-w-0 cursor-pointer"
                  onClick={() => navigate(`/catalog/category/${categoryId}/type/${t.id}`)}
                >
                  <p className="text-[14px] font-bold text-text-primary truncate">{t.name}</p>
                  <p className="text-[11px] font-semibold text-text-muted">Tap to view items</p>
                </div>
                <button onClick={() => navigate(`/catalog/category/${categoryId}/type/${t.id}/add-item`)} className="p-1.5 rounded-xl hover:bg-brand-accent/10 text-text-muted">
                  <LuPlus size={15} />
                </button>
                <button onClick={() => { setEditId(t.id); setEditName(t.name); }} className="p-1.5 rounded-xl hover:bg-brand-accent/10 text-text-muted">
                  <LuPencil size={15} />
                </button>
                <button onClick={() => handleDelete(t.id, t.name)} className="p-1.5 rounded-xl hover:bg-loss/10 text-loss/60">
                  <LuTrash2 size={15} />
                </button>
              </Card>
            ))}
          </div>
        )}
      </div>

      {/* Create type modal */}
      {showCreate && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40" onClick={() => setShowCreate(false)}>
          <div className="bg-white rounded-2xl w-full max-w-sm mx-4 p-6 shadow-2xl" onClick={(e) => e.stopPropagation()}>
            <h3 className="text-[15px] font-extrabold text-text-primary mb-3">New Type</h3>
            <Input placeholder="Type name" value={newName} onChange={(e) => { setNewName(e.target.value); setError(null); }} autoFocus onKeyDown={(e) => { if (e.key === "Enter") handleCreate(); }} />
            {error && <p className="text-loss text-[13px] font-medium mt-2">{error}</p>}
            <div className="flex gap-3 mt-4">
              <Button variant="secondary" onClick={() => { setShowCreate(false); setNewName(""); setError(null); }} className="flex-1">Cancel</Button>
              <Button onClick={handleCreate} className="flex-1" disabled={!newName.trim()}>Create</Button>
            </div>
          </div>
        </div>
      )}

      {/* Rename type modal */}
      {editId && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40" onClick={() => setEditId(null)}>
          <div className="bg-white rounded-2xl w-full max-w-sm mx-4 p-6 shadow-2xl" onClick={(e) => e.stopPropagation()}>
            <h3 className="text-[15px] font-extrabold text-text-primary mb-3">Rename Type</h3>
            <Input placeholder="Type name" value={editName} onChange={(e) => { setEditName(e.target.value); setError(null); }} autoFocus onKeyDown={(e) => { if (e.key === "Enter") handleRename(editId); }} />
            {error && <p className="text-loss text-[13px] font-medium mt-2">{error}</p>}
            <div className="flex gap-3 mt-4">
              <Button variant="secondary" onClick={() => { setEditId(null); setError(null); }} className="flex-1">Cancel</Button>
              <Button onClick={() => handleRename(editId)} className="flex-1" disabled={!editName.trim()}>Save</Button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
