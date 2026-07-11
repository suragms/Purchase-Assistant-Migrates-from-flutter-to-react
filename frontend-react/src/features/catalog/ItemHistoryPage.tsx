import { useParams, useNavigate } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { LuArrowLeft, LuHistory } from "react-icons/lu";
import { useAuthStore } from "../../lib/stores/auth-store";
import { getCatalogItem, getCatalogItemLines } from "../../lib/api/catalog";
import { AppBar, ListSkeleton, Card } from "../../components/ui";

export default function ItemHistoryPage() {
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
      <AppBar title={item ? `${item.name} — Purchase History` : "Purchase History"} leading={<button onClick={() => navigate(-1)} className="p-1.5 -ml-1.5 rounded-xl hover:bg-black/5"><LuArrowLeft size={22} /></button>} />
      <div className="flex-1 px-4 pb-6 space-y-2 overflow-y-auto">
        {isLoading && <ListSkeleton rows={6} />}
        {lines?.map((l, i) => (
          <Card key={i} padding="md">
            <div className="flex justify-between items-start">
              <div className="space-y-0.5">
                <p className="text-[13px] font-bold text-text-primary">{l.entryDate}</p>
                <p className="text-[12px] text-text-muted">Qty: <span className="font-bold text-text-primary">{l.qty} {l.unit}</span></p>
                {l.kgPerUnit != null && <p className="text-[12px] text-text-muted">Weight: <span className="font-bold text-text-primary">{(l.qty * l.kgPerUnit).toFixed(2)} kg</span></p>}
                <p className="text-[12px] text-text-muted">Rate: <span className="font-bold text-text-primary">₹{l.landingCost.toFixed(2)}</span></p>
                {l.profit != null && <p className={`text-[12px] font-bold ${l.profit >= 0 ? "text-gain" : "text-loss"}`}>P&L: ₹{l.profit.toFixed(2)}</p>}
              </div>
              <div className="text-right space-y-0.5">
                {l.supplierName && <p className="text-[11px] text-text-muted">{l.supplierName}</p>}
                {l.purchaseHumanId && <p className="text-[11px] text-text-muted">#{l.purchaseHumanId}</p>}
              </div>
            </div>
            {(l.supplierPhone || l.brokerName) && (
              <div className="mt-1.5 pt-1.5 border-t border-card-border flex gap-3 text-[11px] text-text-muted">
                {l.supplierPhone && <span>📞 {l.supplierPhone}</span>}
                {l.brokerName && <span>Broker: {l.brokerName}</span>}
              </div>
            )}
          </Card>
        ))}
        {!isLoading && lines?.length === 0 && (
          <div className="flex flex-col items-center justify-center py-16 gap-3">
            <LuHistory size={48} className="text-text-muted/40" />
            <p className="text-text-muted text-sm">No purchase history yet</p>
          </div>
        )}
      </div>
    </div>
  );
}
