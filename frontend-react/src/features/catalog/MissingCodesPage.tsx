import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { LuArrowLeft, LuHash, LuBarcode, LuTriangle } from "react-icons/lu";
import { useAuthStore } from "../../lib/stores/auth-store";
import { listCatalogItems, patchCatalogItemCode, patchCatalogItemBarcode } from "../../lib/api/catalog";
import { AppBar, Input, Button, ListSkeleton } from "../../components/ui";

export default function MissingCodesPage() {
  const navigate = useNavigate();
  const businessId = useAuthStore((s) => s.businessId);

  const { data: items, isLoading, refetch } = useQuery({
    queryKey: ["catalog", "all-items", businessId],
    queryFn: () => listCatalogItems(businessId!, { fetchAllPages: true }),
    enabled: !!businessId,
  });

  const missingCodes = items?.filter((i) => !i.itemCode && !i.barcode) || [];
  const [codeInputs, setCodeInputs] = useState<Record<string, { itemCode: string; barcode: string }>>({});

  const handleSetCode = async (itemId: string, field: "itemCode" | "barcode") => {
    const val = codeInputs[itemId]?.[field];
    if (!val) return;
    try {
      if (field === "itemCode") {
        await patchCatalogItemCode(businessId!, itemId, val);
      } else {
        await patchCatalogItemBarcode(businessId!, itemId, val);
      }
      setCodeInputs((prev) => ({ ...prev, [itemId]: { ...prev[itemId], [field]: "" } }));
      refetch();
    } catch { /* ignore */ }
  };

  return (
    <div className="flex flex-col min-h-full">
      <AppBar title="Missing Codes" leading={<button onClick={() => navigate(-1)} className="p-1.5 -ml-1.5 rounded-xl hover:bg-black/5"><LuArrowLeft size={22} /></button>} />
      <div className="flex-1 px-4 pb-6 space-y-3 overflow-y-auto">
        <p className="text-[13px] text-text-muted font-medium flex items-center gap-1">
          <LuTriangle size={14} /> {missingCodes.length} item{missingCodes.length !== 1 ? "s" : ""} missing codes
        </p>
        {isLoading && <ListSkeleton rows={6} />}
        {missingCodes.map((item) => {
          const ci = codeInputs[item.id] || { itemCode: "", barcode: "" };
          return (
            <div key={item.id} className="rounded-xl border border-card-border p-4 space-y-2">
              <button onClick={() => navigate(`/catalog/item/${item.id}`)} className="text-[14px] font-bold text-text-primary hover:underline text-left">{item.name}</button>
              <div className="flex gap-2">
                <Input placeholder="Item code" value={ci.itemCode} onChange={(e) => setCodeInputs((p) => ({ ...p, [item.id]: { ...p[item.id], itemCode: e.target.value, barcode: p[item.id]?.barcode || "" } }))} />
                <Button variant="secondary" size="sm" onClick={() => handleSetCode(item.id, "itemCode")} disabled={!ci.itemCode}>
                  <LuHash size={14} /> Set
                </Button>
              </div>
              <div className="flex gap-2">
                <Input placeholder="Barcode" value={ci.barcode} onChange={(e) => setCodeInputs((p) => ({ ...p, [item.id]: { ...p[item.id], barcode: e.target.value, itemCode: p[item.id]?.itemCode || "" } }))} />
                <Button variant="secondary" size="sm" onClick={() => handleSetCode(item.id, "barcode")} disabled={!ci.barcode}>
                  <LuBarcode size={14} /> Set
                </Button>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
