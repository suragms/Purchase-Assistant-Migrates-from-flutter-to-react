import { useState, useEffect } from "react";
import { useParams, useNavigate } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { LuArrowLeft } from "react-icons/lu";
import { useAuthStore } from "../../lib/stores/auth-store";
import { getCatalogItem, updateCatalogItem } from "../../lib/api/catalog";
import { AppBar, Input, Button, DetailSkeleton } from "../../components/ui";

const UNIT_OPTIONS = ["kg", "box", "piece", "bag", "tin"];

export default function ItemEditPage() {
  const { itemId } = useParams<{ itemId: string }>();
  const navigate = useNavigate();
  const businessId = useAuthStore((s) => s.businessId);

  const { data, isLoading } = useQuery({
    queryKey: ["catalog", "item", businessId, itemId],
    queryFn: () => getCatalogItem(businessId!, itemId!),
    enabled: !!businessId && !!itemId,
  });

  const [name, setName] = useState("");
  const [defaultUnit, setDefaultUnit] = useState("kg");
  const [defaultKgPerBag, setDefaultKgPerBag] = useState("");
  const [defaultLandingCost, setDefaultLandingCost] = useState("");
  const [defaultSellingCost, setDefaultSellingCost] = useState("");
  const [hsnCode, setHsnCode] = useState("");
  const [taxPercent, setTaxPercent] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!data) return;
    setName(data.name || "");
    setDefaultUnit(data.defaultUnit || "kg");
    setDefaultKgPerBag(data.defaultKgPerBag != null ? String(data.defaultKgPerBag) : "");
    setDefaultLandingCost(data.defaultLandingCost != null ? String(data.defaultLandingCost) : "");
    setDefaultSellingCost(data.defaultSellingCost != null ? String(data.defaultSellingCost) : "");
    setHsnCode(data.hsnCode || "");
    setTaxPercent(data.taxPercent != null ? String(data.taxPercent) : "");
  }, [data]);

  const handleSave = async () => {
    if (!name.trim()) return;
    setSaving(true); setError(null);
    try {
      await updateCatalogItem(businessId!, itemId!, {
        name: name.trim(),
        defaultUnit,
        hsnCode: hsnCode || undefined,
        defaultKgPerBag: defaultKgPerBag ? parseFloat(defaultKgPerBag) : undefined,
        defaultLandingCost: defaultLandingCost ? parseFloat(defaultLandingCost) : undefined,
        defaultSellingCost: defaultSellingCost ? parseFloat(defaultSellingCost) : undefined,
        taxPercent: taxPercent ? parseFloat(taxPercent) : undefined,
      });
      navigate(`/catalog/item/${itemId}`);
    } catch (err: any) { setError(err?.response?.data?.detail || "Failed to save"); }
    finally { setSaving(false); }
  };

  if (isLoading) {
    return (
      <div className="flex flex-col min-h-full">
        <AppBar title="Edit Item" leading={<button onClick={() => navigate(-1)} className="p-1.5 -ml-1.5 rounded-xl hover:bg-black/5"><LuArrowLeft size={22} /></button>} />
        <div className="px-4 pb-4"><DetailSkeleton /></div>
      </div>
    );
  }

  return (
    <div className="flex flex-col min-h-full">
      <AppBar title="Edit Item" leading={<button onClick={() => navigate(-1)} className="p-1.5 -ml-1.5 rounded-xl hover:bg-black/5"><LuArrowLeft size={22} /></button>} />
      <div className="flex-1 px-4 pb-6 space-y-4 overflow-y-auto">
        <Input label="Item name" value={name} onChange={(e) => setName(e.target.value)} />
        <div>
          <label className="text-[12px] font-bold text-text-muted block mb-1">Default unit</label>
          <select value={defaultUnit} onChange={(e) => setDefaultUnit(e.target.value)} className="w-full rounded-xl border border-input-border px-3.5 py-[13px] text-[15px] font-medium text-input-text bg-white focus:outline-none focus:border-brand-accent">
            {UNIT_OPTIONS.map((u) => <option key={u} value={u}>{u}</option>)}
          </select>
        </div>
        <Input label="Kg per bag" type="number" step="any" value={defaultKgPerBag} onChange={(e) => setDefaultKgPerBag(e.target.value)} />
        <Input label="Landing cost" type="number" step="any" value={defaultLandingCost} onChange={(e) => setDefaultLandingCost(e.target.value)} />
        <Input label="Selling cost" type="number" step="any" value={defaultSellingCost} onChange={(e) => setDefaultSellingCost(e.target.value)} />
        <Input label="HSN code" value={hsnCode} onChange={(e) => setHsnCode(e.target.value)} />
        <Input label="Tax %" type="number" step="any" value={taxPercent} onChange={(e) => setTaxPercent(e.target.value)} />
        {error && <p className="text-loss text-[13px] font-medium">{error}</p>}
        <Button onClick={handleSave} loading={saving} disabled={!name.trim()}>Save Changes</Button>
      </div>
    </div>
  );
}
