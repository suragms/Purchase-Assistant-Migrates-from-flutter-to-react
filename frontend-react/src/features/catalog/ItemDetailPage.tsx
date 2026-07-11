import { useParams, useNavigate } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { LuArrowLeft, LuPencil, LuTriangle, LuBarcode, LuHash, LuHistory, LuBookOpen, LuGitGraph } from "react-icons/lu";
import { useAuthStore } from "../../lib/stores/auth-store";
import { getCatalogItem } from "../../lib/api/catalog";
import { AppBar, Card, DetailSkeleton, Button } from "../../components/ui";

export default function ItemDetailPage() {
  const { itemId } = useParams<{ itemId: string }>();
  const navigate = useNavigate();
  const businessId = useAuthStore((s) => s.businessId);

  const { data, isLoading, isError, error: fetchErr, refetch } = useQuery({
    queryKey: ["catalog", "item", businessId, itemId],
    queryFn: () => getCatalogItem(businessId!, itemId!),
    enabled: !!businessId && !!itemId,
  });

  if (isLoading) {
    return (
      <div className="flex flex-col min-h-full">
        <AppBar title="Item" leading={<button onClick={() => navigate(-1)} className="p-1.5 -ml-1.5 rounded-xl hover:bg-black/5"><LuArrowLeft size={22} /></button>} />
        <div className="px-4 pb-4"><DetailSkeleton /></div>
      </div>
    );
  }

  if (isError) {
    return (
      <div className="flex flex-col min-h-full">
        <AppBar title="Item" leading={<button onClick={() => navigate(-1)} className="p-1.5 -ml-1.5 rounded-xl hover:bg-black/5"><LuArrowLeft size={22} /></button>} />
        <div className="flex flex-col items-center justify-center py-16 gap-4 px-4">
          <LuTriangle size={48} className="text-loss" />
          <p className="text-text-muted text-sm">{(fetchErr as any)?.message || "Failed to load"}</p>
          <Button variant="secondary" onClick={() => refetch()}>Retry</Button>
        </div>
      </div>
    );
  }

  if (!data) return null;

  const code = data.itemCode;
  const hasCodes = code || data.barcode || data.hsnCode;

  return (
    <div className="flex flex-col min-h-full">
      <AppBar
        title={data.name}
        leading={<button onClick={() => navigate(-1)} className="p-1.5 -ml-1.5 rounded-xl hover:bg-black/5"><LuArrowLeft size={22} /></button>}
        actions={[
          <button key="edit" onClick={() => navigate(`/catalog/item/${itemId}/edit`)} className="flex items-center gap-1.5 h-9 px-3 rounded-xl bg-brand-accent/10 text-brand-accent text-[13px] font-bold hover:bg-brand-accent/20">
            <LuPencil size={14} /> <span className="hidden sm:inline">Edit</span>
          </button>,
        ]}
      />

      <div className="flex-1 px-4 pb-6 space-y-3 overflow-y-auto">
        {/* Codes */}
        {hasCodes && (
          <Card padding="md">
            <div className="space-y-1.5">
              {code && <Row label="Item Code" value={code} icon={<LuHash size={14} />} />}
              {data.barcode && <Row label="Barcode" value={data.barcode} icon={<LuBarcode size={14} />} />}
              {data.hsnCode && <Row label="HSN" value={data.hsnCode} />}
            </div>
          </Card>
        )}

        {/* Unit info */}
        <Card padding="md">
          <h3 className="text-[13px] font-bold text-text-muted mb-2">Units</h3>
          <div className="space-y-1.5">
            <Row label="Default unit" value={data.defaultUnit || "—"} />
            {data.defaultPurchaseUnit && <Row label="Purchase unit" value={data.defaultPurchaseUnit} />}
            {data.defaultSaleUnit && <Row label="Sale unit" value={data.defaultSaleUnit} />}
            {data.defaultKgPerBag != null && <Row label="Kg per bag" value={String(data.defaultKgPerBag)} />}
            {data.defaultItemsPerBox != null && <Row label="Items per box" value={String(data.defaultItemsPerBox)} />}
            {data.defaultWeightPerTin != null && <Row label="Weight per tin" value={String(data.defaultWeightPerTin)} />}
          </div>
        </Card>

        {/* Pricing */}
        {(data.defaultLandingCost != null || data.defaultSellingCost != null || data.lastPurchasePrice != null) && (
          <Card padding="md">
            <h3 className="text-[13px] font-bold text-text-muted mb-2">Pricing</h3>
            <div className="space-y-1.5">
              {data.defaultLandingCost != null && <Row label="Landing cost" value={`₹${data.defaultLandingCost.toFixed(2)}`} />}
              {data.defaultSellingCost != null && <Row label="Selling cost" value={`₹${data.defaultSellingCost.toFixed(2)}`} />}
              {data.lastPurchasePrice != null && <Row label="Last purchase rate" value={`₹${data.lastPurchasePrice.toFixed(2)}`} />}
              {data.lastSellingRate != null && <Row label="Last selling rate" value={`₹${data.lastSellingRate.toFixed(2)}`} />}
              {data.taxPercent != null && <Row label="Tax" value={`${data.taxPercent}%`} />}
            </div>
          </Card>
        )}

        {/* Last purchase info */}
        {data.lastSupplierName && (
          <Card padding="md">
            <h3 className="text-[13px] font-bold text-text-muted mb-2">Last Purchase</h3>
            <div className="space-y-1.5">
              {data.lastSupplierName && <Row label="Supplier" value={data.lastSupplierName} />}
              {data.lastBrokerName && <Row label="Broker" value={data.lastBrokerName} />}
              {data.lastPurchaseDate && <Row label="Date" value={data.lastPurchaseDate} />}
              {data.lastLineQty != null && <Row label="Qty" value={`${data.lastLineQty} ${data.lastLineUnit || ""}`} />}
              {data.lastLineWeightKg != null && <Row label="Weight" value={`${data.lastLineWeightKg} kg`} />}
              {data.lastPurchaseDelivered != null && <Row label="Delivered" value={data.lastPurchaseDelivered ? "Yes" : "No"} />}
            </div>
          </Card>
        )}

        {/* Action links */}
        <div className="flex flex-col gap-2 pt-2">
          <Button variant="secondary" onClick={() => navigate(`/catalog/item/${itemId}/timeline`)}>
            <LuGitGraph size={16} /> View Timeline
          </Button>
          <Button variant="secondary" onClick={() => navigate(`/catalog/item/${itemId}/purchase-history`)}>
            <LuHistory size={16} /> Purchase History
          </Button>
          <Button variant="secondary" onClick={() => navigate(`/catalog/item/${itemId}/ledger`)}>
            <LuBookOpen size={16} /> Trade Ledger
          </Button>
        </div>
      </div>
    </div>
  );
}

function Row({ label, value, icon }: { label: string; value: string; icon?: React.ReactNode }) {
  return (
    <div className="flex justify-between items-center">
      <span className="text-[12px] font-semibold text-text-muted flex items-center gap-1">
        {icon} {label}
      </span>
      <span className="text-[12px] font-bold text-text-primary text-right">{value}</span>
    </div>
  );
}
