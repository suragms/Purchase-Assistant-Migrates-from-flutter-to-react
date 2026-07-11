import { useParams, useNavigate } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { LuArrowLeft, LuGitGraph } from "react-icons/lu";
import { useAuthStore } from "../../lib/stores/auth-store";
import { getCatalogItem, getCatalogItemLines } from "../../lib/api/catalog";
import { AppBar, ListSkeleton, Card } from "../../components/ui";

export default function ItemTimelinePage() {
  const { itemId } = useParams<{ itemId: string }>();
  const navigate = useNavigate();
  const businessId = useAuthStore((s) => s.businessId);

  const { data: item } = useQuery({
    queryKey: ["catalog", "item", businessId, itemId],
    queryFn: () => getCatalogItem(businessId!, itemId!),
    enabled: !!businessId && !!itemId,
  });

  const { data: lines, isLoading } = useQuery({
    queryKey: ["catalog", "item-lines", businessId, itemId],
    queryFn: () => getCatalogItemLines(businessId!, itemId!, { limit: 50 }),
    enabled: !!businessId && !!itemId,
  });

  return (
    <div className="flex flex-col min-h-full">
      <AppBar title={item ? `${item.name} — Timeline` : "Timeline"} leading={<button onClick={() => navigate(-1)} className="p-1.5 -ml-1.5 rounded-xl hover:bg-black/5"><LuArrowLeft size={22} /></button>} />
      <div className="flex-1 px-4 pb-6 space-y-2 overflow-y-auto">
        {isLoading && <ListSkeleton rows={6} />}
        {lines?.map((l, i) => (
          <Card key={i} padding="md">
            <div className="flex items-start gap-3">
              <div className="w-2 h-2 rounded-full bg-brand-accent mt-1.5 shrink-0" />
              <div className="flex-1 min-w-0">
                <div className="flex justify-between items-baseline">
                  <span className="text-[13px] font-bold text-text-primary">{l.entryDate}</span>
                  {l.purchaseHumanId && (
                    <span className="text-[11px] text-text-muted font-medium">#{l.purchaseHumanId}</span>
                  )}
                </div>
                <div className="mt-1 text-[12px] text-text-muted space-y-0.5">
                  <p>Qty: <span className="font-bold text-text-primary">{l.qty} {l.unit}</span></p>
                  {l.kgPerUnit != null && <p>Weight: <span className="font-bold text-text-primary">{(l.qty * l.kgPerUnit).toFixed(2)} kg</span></p>}
                  <p>Landing: <span className="font-bold text-text-primary">₹{l.landingCost.toFixed(2)}</span></p>
                  {l.sellingPrice != null && <p>Selling: <span className="font-bold text-text-primary">₹{l.sellingPrice.toFixed(2)}</span></p>}
                  {l.profit != null && (
                    <p className={l.profit >= 0 ? "text-gain" : "text-loss"}>
                      Profit: <span className="font-bold">₹{l.profit.toFixed(2)}</span>
                    </p>
                  )}
                  {l.unitResolution && Object.keys(l.unitResolution).length > 0 && (
                    <p className="text-[11px] text-text-muted">Resolution: {JSON.stringify(l.unitResolution)}</p>
                  )}
                </div>
                {(l.supplierName || l.brokerName) && (
                  <div className="mt-1.5 flex gap-3 flex-wrap text-[11px] text-text-muted">
                    {l.supplierName && <span>Supplier: {l.supplierName}</span>}
                    {l.brokerName && <span>Broker: {l.brokerName}</span>}
                  </div>
                )}
              </div>
            </div>
          </Card>
        ))}
        {!isLoading && lines?.length === 0 && (
          <div className="flex flex-col items-center justify-center py-16 gap-3">
            <LuGitGraph size={48} className="text-text-muted/40" />
            <p className="text-text-muted text-sm">No timeline entries yet</p>
          </div>
        )}
      </div>
    </div>
  );
}
