import { useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { LuArrowLeft, LuPlus, LuScanLine } from "react-icons/lu";
import { useAuthStore } from "../../lib/stores/auth-store";
import { listCategories, listCategoryTypes, createCatalogItemFromScan } from "../../lib/api/catalog";
import { AppBar, Input, Button, Card } from "../../components/ui";

export default function QuickAddFromScanPage() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const businessId = useAuthStore((s) => s.businessId);

  const initialBarcode = searchParams.get("barcode") || "";
  const initialItemCode = searchParams.get("itemCode") || "";

  const [categoryId, setCategoryId] = useState("");
  const [typeId, setTypeId] = useState("");
  const [name, setName] = useState("");
  const [defaultUnit, setDefaultUnit] = useState("kg");
  const [defaultKgPerBag, setDefaultKgPerBag] = useState("");
  const [barcode, setBarcode] = useState(initialBarcode);
  const [itemCode, setItemCode] = useState(initialItemCode);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [successId, setSuccessId] = useState<string | null>(null);

  const { data: cats } = useQuery({
    queryKey: ["catalog", "categories", businessId],
    queryFn: () => listCategories(businessId!),
    enabled: !!businessId,
  });

  const { data: types } = useQuery({
    queryKey: ["catalog", "types", businessId, categoryId],
    queryFn: () => listCategoryTypes(businessId!, categoryId),
    enabled: !!businessId && !!categoryId,
  });

  const handleSubmit = async () => {
    if (!name.trim() || !typeId) return;
    setSaving(true); setError(null);
    try {
      const item = await createCatalogItemFromScan(businessId!, {
        barcode: barcode || `SCAN-${Date.now()}`,
        itemCode: itemCode || `AUTO-${Date.now()}`,
        name: name.trim(),
        typeId,
        defaultUnit: defaultUnit || undefined,
        defaultKgPerBag: defaultKgPerBag ? parseFloat(defaultKgPerBag) : undefined,
      });
      setSuccessId(item.id);
      setName(""); setBarcode(""); setItemCode(""); setDefaultKgPerBag("");
    } catch (err: any) { setError(err?.response?.data?.detail || "Failed to create item"); }
    finally { setSaving(false); }
  };

  return (
    <div className="flex flex-col min-h-full">
      <AppBar title="Quick Add from Scan" leading={<button onClick={() => navigate(-1)} className="p-1.5 -ml-1.5 rounded-xl hover:bg-black/5"><LuArrowLeft size={22} /></button>} />
      <div className="flex-1 px-4 pb-6 space-y-4 overflow-y-auto">
        {(barcode || itemCode) && (
          <Card padding="md" className="bg-brand-accent/5 border border-brand-accent/10">
            <div className="flex items-center gap-2 text-[13px] font-medium text-text-primary">
              <LuScanLine size={16} className="text-brand-accent" />
              {barcode && <span>Barcode: <span className="font-bold">{barcode}</span></span>}
              {itemCode && <span>Code: <span className="font-bold">{itemCode}</span></span>}
            </div>
          </Card>
        )}

        <div>
          <label className="text-[12px] font-bold text-text-muted block mb-1">Category</label>
          <select value={categoryId} onChange={(e) => { setCategoryId(e.target.value); setTypeId(""); }} className="w-full rounded-xl border border-input-border px-3.5 py-[13px] text-[15px] font-medium text-input-text bg-white focus:outline-none focus:border-brand-accent">
            <option value="">-- Select --</option>
            {cats?.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
          </select>
        </div>

        {categoryId && (
          <div>
            <label className="text-[12px] font-bold text-text-muted block mb-1">Type (required)</label>
            <select value={typeId} onChange={(e) => setTypeId(e.target.value)} className="w-full rounded-xl border border-input-border px-3.5 py-[13px] text-[15px] font-medium text-input-text bg-white focus:outline-none focus:border-brand-accent">
              <option value="">-- Select --</option>
              {types?.map((t) => <option key={t.id} value={t.id}>{t.name}</option>)}
            </select>
          </div>
        )}

        <Input label="Item name" value={name} onChange={(e) => setName(e.target.value)} />
        <div>
          <label className="text-[12px] font-bold text-text-muted block mb-1">Default unit</label>
          <select value={defaultUnit} onChange={(e) => setDefaultUnit(e.target.value)} className="w-full rounded-xl border border-input-border px-3.5 py-[13px] text-[15px] font-medium text-input-text bg-white focus:outline-none focus:border-brand-accent">
            {["kg", "box", "piece", "bag", "tin"].map((u) => <option key={u} value={u}>{u}</option>)}
          </select>
        </div>
        <Input label="Kg per bag (optional)" type="number" step="any" value={defaultKgPerBag} onChange={(e) => setDefaultKgPerBag(e.target.value)} />

        {error && <p className="text-loss text-[13px] font-medium">{error}</p>}

        {successId && (
          <Card padding="md" className="bg-gain/10 border border-gain/20">
            <p className="text-[13px] font-bold text-gain">Item created!</p>
            <Button variant="secondary" size="sm" onClick={() => navigate(`/catalog/item/${successId}`)} className="mt-2">View item</Button>
          </Card>
        )}

        <Button onClick={handleSubmit} loading={saving} disabled={!name.trim() || !typeId}>
          <LuPlus size={16} /> Create from Scan
        </Button>
      </div>
    </div>
  );
}
