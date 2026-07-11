import { useParams, useNavigate } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { LuArrowLeft, LuBookOpen, LuTrendingUp, LuDollarSign } from "react-icons/lu";
import { useAuthStore } from "../../lib/stores/auth-store";
import { getCatalogItem, getCatalogItemLines, getCatalogItemInsights } from "../../lib/api/catalog";
import { AppBar, ListSkeleton, Card } from "../../components/ui";

export default function TradeLedgerPage() {
  const { itemId } = useParams<{ itemId: string }>();
  const navigate = useNavigate();
  const businessId = useAuthStore((s) => s.businessId);

  const { data: item } = useQuery({
    queryKey: ["catalog", "item", businessId, itemId],
    queryFn: () => getCatalogItem(businessId!, itemId!),
    enabled: !!businessId && !!itemId,
  });

  const { data: insights } = useQuery({
    queryKey: ["catalog", "item-insights", businessId, itemId],
    queryFn: () => getCatalogItemInsights(businessId!, itemId!),
    enabled: !!businessId && !!itemId,
  });

  const { data: lines, isLoading } = useQuery({
    queryKey: ["catalog", "item-lines", businessId, itemId],
    queryFn: () => getCatalogItemLines(businessId!, itemId!, { limit: 50 }),
    enabled: !!businessId && !!itemId,
  });

  return (
    <div className="flex flex-col min-h-full">
      <AppBar title={item ? `${item.name} — Ledger` : "Trade Ledger"} leading={<button onClick={() => navigate(-1)} className="p-1.5 -ml-1.5 rounded-xl hover:bg-black/5"><LuArrowLeft size={22} /></button>} />
      <div className="flex-1 px-4 pb-6 space-y-3 overflow-y-auto">
        {isLoading && <ListSkeleton rows={6} />}

        {insights && (
          <Card padding="md">
            <h3 className="text-[13px] font-bold text-text-muted mb-2 flex items-center gap-1"><LuTrendingUp size={14} /> Insights</h3>
            <div className="grid grid-cols-2 gap-3">
              <div className="rounded-lg bg-card-bg p-3">
                <p className="text-[11px] text-text-muted font-medium">Total Lines</p>
                <p className="text-[18px] font-bold text-text-primary">{insights.lineCount}</p>
              </div>
              <div className="rounded-lg bg-card-bg p-3">
                <p className="text-[11px] text-text-muted font-medium">Total profit</p>
                <p className={`text-[18px] font-bold ${insights.totalProfit >= 0 ? "text-gain" : "text-loss"}`}>
                  ₹{insights.totalProfit.toFixed(2)}
                </p>
              </div>
              {insights.avgLanding != null && (
                <div className="rounded-lg bg-card-bg p-3">
                  <p className="text-[11px] text-text-muted font-medium">Avg landing</p>
                  <p className="text-[18px] font-bold text-text-primary">₹{insights.avgLanding.toFixed(2)}</p>
                </div>
              )}
              {insights.avgSelling != null && (
                <div className="rounded-lg bg-card-bg p-3">
                  <p className="text-[11px] text-text-muted font-medium">Avg selling</p>
                  <p className="text-[18px] font-bold text-text-primary">₹{insights.avgSelling.toFixed(2)}</p>
                </div>
              )}
              {insights.profitMarginPct != null && (
                <div className="rounded-lg bg-card-bg p-3">
                  <p className="text-[11px] text-text-muted font-medium">Margin</p>
                  <p className={`text-[18px] font-bold ${insights.profitMarginPct >= 0 ? "text-gain" : "text-loss"}`}>
                    {insights.profitMarginPct.toFixed(1)}%
                  </p>
                </div>
              )}
              {insights.lastEntryDate && (
                <div className="rounded-lg bg-card-bg p-3">
                  <p className="text-[11px] text-text-muted font-medium">Last entry</p>
                  <p className="text-[18px] font-bold text-text-primary">{insights.lastEntryDate}</p>
                </div>
              )}
            </div>
          </Card>
        )}

        <h3 className="text-[13px] font-bold text-text-muted px-0.5 flex items-center gap-1"><LuBookOpen size={14} /> Entries</h3>

        {lines?.map((l, i) => (
          <Card key={i} padding="md">
            <div className="flex items-start gap-2">
              <LuDollarSign size={14} className="text-text-muted mt-0.5 shrink-0" />
              <div className="flex-1 min-w-0">
                <div className="flex justify-between items-baseline">
                  <span className="text-[13px] font-bold text-text-primary">{l.entryDate}</span>
                  {l.purchaseHumanId && <span className="text-[11px] text-text-muted font-mono">#{l.purchaseHumanId}</span>}
                </div>
                <div className="mt-1 grid grid-cols-2 gap-x-4 gap-y-0.5 text-[12px] text-text-muted">
                  <span>Qty: <b className="text-text-primary">{l.qty} {l.unit}</b></span>
                  {l.landingCostPerKg != null && <span>₹/kg: <b className="text-text-primary">₹{l.landingCostPerKg.toFixed(2)}</b></span>}
                  <span>Landing: <b className="text-text-primary">₹{l.landingCost.toFixed(2)}</b></span>
                  {l.sellingPrice != null && <span>Selling: <b className="text-text-primary">₹{l.sellingPrice.toFixed(2)}</b></span>}
                </div>
              </div>
            </div>
          </Card>
        ))}
        {!isLoading && lines?.length === 0 && (
          <div className="flex flex-col items-center justify-center py-16 gap-3">
            <LuBookOpen size={48} className="text-text-muted/40" />
            <p className="text-text-muted text-sm">No ledger entries yet</p>
          </div>
        )}
      </div>
    </div>
  );
}
