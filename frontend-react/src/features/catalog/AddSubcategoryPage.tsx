import { useState } from "react";
import { useParams, useNavigate } from "react-router-dom";
import { useAuthStore } from "../../lib/stores/auth-store";
import { createCategoryType } from "../../lib/api/catalog";
import { AppBar, Input, Button } from "../../components/ui";
import { LuArrowLeft } from "react-icons/lu";

export default function AddSubcategoryPage() {
  const { categoryId } = useParams<{ categoryId: string }>();
  const businessId = useAuthStore((s) => s.businessId);
  const navigate = useNavigate();
  const [name, setName] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  const handleSave = async () => {
    if (!name.trim()) return;
    setSaving(true); setError(null);
    try {
      await createCategoryType(businessId!, categoryId!, name.trim());
      navigate(`/catalog/category/${categoryId}`);
    } catch (err: any) { setError(err?.response?.data?.detail || "Failed to create"); }
    finally { setSaving(false); }
  };

  return (
    <div className="flex flex-col min-h-full">
      <AppBar title="New Subcategory" leading={<button onClick={() => navigate(-1)} className="p-1.5 -ml-1.5 rounded-xl hover:bg-black/5"><LuArrowLeft size={22} /></button>} />
      <div className="flex-1 px-4 pb-4 space-y-4">
        <Input label="Type / Subcategory name" value={name} onChange={(e) => setName(e.target.value)} placeholder="e.g. Basmati, Turmeric" autoFocus onKeyDown={(e) => { if (e.key === "Enter") handleSave(); }} />
        {error && <p className="text-loss text-[13px] font-medium">{error}</p>}
        <Button onClick={handleSave} loading={saving} disabled={!name.trim()}>Create Type</Button>
      </div>
    </div>
  );
}
