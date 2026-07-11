import { useState, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { LuSearch, LuPlus, LuX, LuFolder, LuTriangle, LuPencil, LuTrash2, LuPackage } from "react-icons/lu";
import { useAuthStore } from "../../lib/stores/auth-store";
import { listCategories, createCategory, updateCategory, deleteCategory } from "../../lib/api/catalog";
import { AppBar, Input, ListSkeleton, Card, Button } from "../../components/ui";

function useDebounce<T>(value: T, delay: number): T {
  const [debounced, setDebounced] = useState(value);
  useEffect(() => { const t = setTimeout(() => setDebounced(value), delay); return () => clearTimeout(t); }, [value, delay]);
  return debounced;
}

export default function CatalogPage() {
  const businessId = useAuthStore((s) => s.businessId);
  const navigate = useNavigate();
  const [search, setSearch] = useState("");
  const debouncedSearch = useDebounce(search, 200);

  const [showCreate, setShowCreate] = useState(false);
  const [newName, setNewName] = useState("");
  const [editId, setEditId] = useState<string | null>(null);
  const [editName, setEditName] = useState("");
  const [error, setError] = useState<string | null>(null);

  const { data, isLoading, isError, error: fetchErr, refetch } = useQuery({
    queryKey: ["catalog", "categories", businessId],
    queryFn: () => listCategories(businessId!),
    enabled: !!businessId,
  });

  const filtered = data?.filter((c) =>
    !debouncedSearch || c.name.toLowerCase().includes(debouncedSearch.toLowerCase())
  ) ?? [];

  const handleCreate = async () => {
    if (!newName.trim()) return;
    setError(null);
    try {
      await createCategory(businessId!, newName.trim());
      setNewName("");
      setShowCreate(false);
      refetch();
    } catch (err: any) {
      setError(err?.response?.data?.detail || "Failed to create category");
    }
  };

  const handleRename = async (id: string) => {
    if (!editName.trim()) return;
    setError(null);
    try {
      await updateCategory(businessId!, id, editName.trim());
      setEditId(null);
      setEditName("");
      refetch();
    } catch (err: any) {
      setError(err?.response?.data?.detail || "Failed to rename");
    }
  };

  const handleDelete = async (id: string, name: string) => {
    if (!window.confirm(`Delete category "${name}"? Items must be moved or deleted first.`)) return;
    setError(null);
    try {
      await deleteCategory(businessId!, id);
      refetch();
    } catch (err: any) {
      setError(err?.response?.data?.detail || "Failed to delete");
    }
  };

  return (
    <div className="flex flex-col min-h-full">
      <AppBar
        title="Catalog"
        actions={[
          <button
            key="add"
            onClick={() => setShowCreate(true)}
            className="flex items-center gap-1.5 h-9 px-3 rounded-xl bg-brand-accent text-white text-[13px] font-bold shadow-[0_4px_12px_rgba(21,154,138,0.30)] hover:shadow-[0_6px_16px_rgba(21,154,138,0.40)] active:scale-[0.97] transition-all"
          >
            <LuPlus size={16} />
            <span className="hidden sm:inline">Add Category</span>
          </button>,
        ]}
      />

      <div className="px-4 pb-2">
        <Input
          placeholder="Search categories..."
          leftIcon={<LuSearch size={18} />}
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          rightIcon={search ? <button onClick={() => setSearch("")} className="p-1"><LuX size={16} /></button> : undefined}
        />
      </div>

      <div className="flex-1 px-4 pb-4">
        {isLoading ? (
          <ListSkeleton rows={8} rowHeight={64} />
        ) : isError ? (
          <div className="flex flex-col items-center justify-center py-16 gap-4">
            <LuTriangle size={48} className="text-loss" />
            <p className="text-text-muted text-sm">{(fetchErr as any)?.message || "Failed to load"}</p>
            <Button variant="secondary" onClick={() => refetch()}>Retry</Button>
          </div>
        ) : filtered.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 gap-4">
            <LuPackage size={48} className="text-text-muted/40" />
            <p className="text-text-muted font-semibold">No categories yet</p>
            <p className="text-text-muted/60 text-sm">Create your first category to organize items</p>
          </div>
        ) : (
          <div className="flex flex-col gap-2">
            {filtered.map((cat) => (
              <Card key={cat.id} padding="sm" className="flex items-center gap-3">
                <div className="p-2 rounded-xl bg-brand-accent/10 text-brand-accent shrink-0">
                  <LuFolder size={20} />
                </div>
                <div
                  className="flex-1 min-w-0 cursor-pointer"
                  onClick={() => navigate(`/catalog/category/${cat.id}`)}
                >
                  <p className="text-[14px] font-bold text-text-primary truncate">{cat.name}</p>
                  <p className="text-[11px] font-semibold text-text-muted">Tap to view types</p>
                </div>
                <button
                  onClick={() => { setEditId(cat.id); setEditName(cat.name); }}
                  className="p-1.5 rounded-xl hover:bg-brand-accent/10 text-text-muted"
                >
                  <LuPencil size={15} />
                </button>
                <button
                  onClick={() => handleDelete(cat.id, cat.name)}
                  className="p-1.5 rounded-xl hover:bg-loss/10 text-loss/60"
                >
                  <LuTrash2 size={15} />
                </button>
              </Card>
            ))}
          </div>
        )}

        {/* Quick actions */}
        <div className="mt-4 flex gap-2">
          <Button variant="secondary" onClick={() => navigate("/catalog/taxonomy")} className="flex-1">
            Manage Types
          </Button>
          <Button variant="secondary" onClick={() => navigate("/catalog/quick-add")} className="flex-1">
            Quick Add Item
          </Button>
        </div>
      </div>

      {/* Create modal */}
      {showCreate && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40" onClick={() => setShowCreate(false)}>
          <div className="bg-white rounded-2xl w-full max-w-sm mx-4 p-6 shadow-2xl" onClick={(e) => e.stopPropagation()}>
            <h3 className="text-[15px] font-extrabold text-text-primary mb-3">New Category</h3>
            <Input
              placeholder="Category name"
              value={newName}
              onChange={(e) => { setNewName(e.target.value); setError(null); }}
              autoFocus
              onKeyDown={(e) => { if (e.key === "Enter") handleCreate(); }}
            />
            {error && <p className="text-loss text-[13px] font-medium mt-2">{error}</p>}
            <div className="flex gap-3 mt-4">
              <Button variant="secondary" onClick={() => { setShowCreate(false); setNewName(""); setError(null); }} className="flex-1">Cancel</Button>
              <Button onClick={handleCreate} className="flex-1" disabled={!newName.trim()}>Create</Button>
            </div>
          </div>
        </div>
      )}

      {/* Rename modal */}
      {editId && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40" onClick={() => setEditId(null)}>
          <div className="bg-white rounded-2xl w-full max-w-sm mx-4 p-6 shadow-2xl" onClick={(e) => e.stopPropagation()}>
            <h3 className="text-[15px] font-extrabold text-text-primary mb-3">Rename Category</h3>
            <Input
              placeholder="Category name"
              value={editName}
              onChange={(e) => { setEditName(e.target.value); setError(null); }}
              autoFocus
              onKeyDown={(e) => { if (e.key === "Enter") handleRename(editId); }}
            />
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
