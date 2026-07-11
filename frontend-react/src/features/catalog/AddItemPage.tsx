import { useState } from "react";
import { useParams, useNavigate } from "react-router-dom";
import { useAuthStore } from "../../lib/stores/auth-store";
import { createCatalogItem } from "../../lib/api/catalog";
import { AppBar, Input, Button } from "../../components/ui";
import { LuArrowLeft } from "react-icons/lu";

const UNIT_OPTIONS = ["kg", "box", "piece", "bag", "tin"];

export default function AddItemPage() {
  const { categoryId, typeId } = useParams<{ categoryId: string; typeId: string }>();
  const businessId = useAuthStore((s) => s.businessId);
  const navigate = useNavigate();

  const [name, setName] = useState("");
  const [defaultUnit, setDefaultUnit] = useState("kg");
  const [defaultKgPerBag, setDefaultKgPerBag] = useState("");
  const [defaultItemsPerBox, setDefaultItemsPerBox] = useState("");
  const [defaultWeightPerTin, setDefaultWeightPerTin] = useState("");
  const [defaultLandingCost, setDefaultLandingCost] = useState("");
  const [defaultSellingCost, setDefaultSellingCost] = useState("");
  const [hsnCode, setHsnCode] = useState("");
  const [itemCode, setItemCode] = useState("");
  const [barcode, setBarcode] = useState("");
  const [taxPercent, setTaxPercent] = useState("");
  const [packageType, setPackageType] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  const handleSave = async () => {
    if (!name.trim()) return;
    setSaving(true); setError(null);
    try {
      await createCatalogItem(businessId!, {
        categoryId: categoryId!,
        typeId,
        name: name.trim(),
        defaultUnit,
        hsnCode: hsnCode || undefined,
        itemCode: itemCode || undefined,
        barcode: barcode || undefined,
        packageType: packageType || undefined,
        defaultKgPerBag: defaultKgPerBag ? parseFloat(defaultKgPerBag) : undefined,
        defaultItemsPerBox: defaultItemsPerBox ? parseFloat(defaultItemsPerBox) : undefined,
        defaultWeightPerTin: defaultWeightPerTin ? parseFloat(defaultWeightPerTin) : undefined,
        defaultLandingCost: defaultLandingCost ? parseFloat(defaultLandingCost) : undefined,
        defaultSellingCost: defaultSellingCost ? parseFloat(defaultSellingCost) : undefined,
        taxPercent: taxPercent ? parseFloat(taxPercent) : undefined,
      });
      navigate(`/catalog/category/${categoryId}/type/${typeId}`);
    } catch (err: any) { setError(err?.response?.data?.detail || "Failed to create item"); }
    finally { setSaving(false); }
  };

  return (
    <div className="flex flex-col min-h-full">
      <AppBar title="New Item" leading={<button onClick={() => navigate(-1)} className="p-1.5 -ml-1.5 rounded-xl hover:bg-black/5"><LuArrowLeft size={22} /></button>} />
      <div className="flex-1 px-4 pb-6 space-y-4 overflow-y-auto">
        <Input label="Item name" value={name} onChange={(e) => setName(e.target.value)} placeholder="Item name" autoFocus />

        <div>
          <label className="text-[12px] font-bold text-text-muted block mb-1">Default unit</label>
          <select value={defaultUnit} onChange={(e) => setDefaultUnit(e.target.value)} className="w-full rounded-xl border border-input-border px-3.5 py-[13px] text-[15px] font-medium text-input-text bg-white focus:outline-none focus:border-brand-accent focus:ring-2 focus:ring-brand-accent/20">
            {UNIT_OPTIONS.map((u) => <option key={u} value={u}>{u}</option>)}
          </select>
        </div>

        <Input label="Kg per bag" type="number" step="any" value={defaultKgPerBag} onChange={(e) => setDefaultKgPerBag(e.target.value)} />
        <Input label="Items per box" type="number" step="any" value={defaultItemsPerBox} onChange={(e) => setDefaultItemsPerBox(e.target.value)} />
        <Input label="Weight per tin (kg)" type="number" step="any" value={defaultWeightPerTin} onChange={(e) => setDefaultWeightPerTin(e.target.value)} />
        <Input label="Default landing cost" type="number" step="any" value={defaultLandingCost} onChange={(e) => setDefaultLandingCost(e.target.value)} />
        <Input label="Default selling cost" type="number" step="any" value={defaultSellingCost} onChange={(e) => setDefaultSellingCost(e.target.value)} />
        <Input label="HSN code" value={hsnCode} onChange={(e) => setHsnCode(e.target.value)} />
        <Input label="Item code" value={itemCode} onChange={(e) => setItemCode(e.target.value)} />
        <Input label="Barcode" value={barcode} onChange={(e) => setBarcode(e.target.value)} />
        <Input label="Tax %" type="number" step="any" value={taxPercent} onChange={(e) => setTaxPercent(e.target.value)} />
        <Input label="Package type" value={packageType} onChange={(e) => setPackageType(e.target.value)} />
        {error && <p className="text-loss text-[13px] font-medium">{error}</p>}
        <Button onClick={handleSave} loading={saving} disabled={!name.trim()}>Create Item</Button>
      </div>
    </div>
  );
}
