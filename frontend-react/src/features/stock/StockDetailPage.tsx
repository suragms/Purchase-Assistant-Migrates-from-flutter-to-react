import { useState } from "react";
import { useParams, useNavigate } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import {
  LuArrowLeft,
  LuTriangle,
  LuExternalLink,
  LuPenLine,
} from "react-icons/lu";
import { useAuthStore } from "../../lib/stores/auth-store";
import { getStockDetail } from "../../lib/api/stock";
import { StockStatusBadge } from "./StockStatusBadge";
import { AppBar, Card, Button, DetailSkeleton, Input } from "../../components/ui";

const ADJUSTMENT_TYPES = [
  "Purchase", "Sale", "Usage", "Transfer", "Manual",
  "Damaged", "Expired", "Correction", "Verification", "Opening Stock",
] as const;

export default function StockDetailPage() {
  const { itemId } = useParams<{ itemId: string }>();
  const navigate = useNavigate();
  const businessId = useAuthStore((s) => s.businessId);

  const { data, isLoading, isError, error, refetch } = useQuery({
    queryKey: ["stock", "detail", businessId, itemId],
    queryFn: () => getStockDetail(businessId!, itemId!),
    enabled: !!businessId && !!itemId,
  });

  const [showForm, setShowForm] = useState(false);
  const [newQty, setNewQty] = useState("");
  const [adjustmentType, setAdjustmentType] = useState("Verification");
  const [reason, setReason] = useState("");
  const [saving, setSaving] = useState(false);
  const [qtyError, setQtyError] = useState<string | null>(null);
  const [saveError, setSaveError] = useState<string | null>(null);

  const parsedQty = (() => {
    const t = newQty.trim().replace(/,/g, "");
    if (!t) return null;
    const v = parseFloat(t);
    if (isNaN(v) || v < 0) return null;
    return v;
  })();

  const canSave = !saving && parsedQty !== null;

  const handleSave = async () => {
    if (!canSave) {
      if (parsedQty === null) setQtyError("Enter a valid quantity");
      return;
    }
    if (!data) return;
    setSaving(true);
    setSaveError(null);

    const { patchStockItem } = await import("../../lib/api/stock");
    try {
      await patchStockItem(businessId!, itemId!, {
        newQty: parsedQty!,
        adjustmentType: adjustmentType.toLowerCase().replace(/\s+/g, "_"),
        reason: reason || undefined,
        lastSeenStockVersion: data.stockVersion,
        idempotencyKey: crypto.randomUUID(),
      });
      refetch();
      setShowForm(false);
      setNewQty("");
      setReason("");
      setAdjustmentType("Verification");
    } catch (err: any) {
      if (err?.response?.status === 409) {
        setSaveError("Stock was updated by another user. Please review and try again.");
        refetch();
      } else {
        setSaveError(err?.response?.data?.message || err?.message || "Failed to save");
      }
    } finally {
      setSaving(false);
    }
  };

  if (isLoading) {
    return (
      <div className="flex flex-col min-h-full">
        <AppBar
          title="Stock Detail"
          leading={
            <button onClick={() => navigate(-1)} className="p-1.5 -ml-1.5 rounded-xl hover:bg-black/5">
              <LuArrowLeft size={22} />
            </button>
          }
        />
        <div className="px-4 pb-4">
          <DetailSkeleton />
        </div>
      </div>
    );
  }

  if (isError) {
    const status = (error as any)?.response?.status;
    return (
      <div className="flex flex-col min-h-full">
        <AppBar
          title="Stock Detail"
          leading={
            <button onClick={() => navigate(-1)} className="p-1.5 -ml-1.5 rounded-xl hover:bg-black/5">
              <LuArrowLeft size={22} />
            </button>
          }
        />
        <div className="flex flex-col items-center justify-center py-16 gap-4 px-4">
          <LuTriangle size={48} className="text-loss" />
          <p className="text-text-muted text-sm">
            {status === 404
              ? "Stock item not found"
              : (error as any)?.message || "Failed to load stock detail"}
          </p>
          <Button variant="secondary" onClick={() => refetch()}>
            Retry
          </Button>
        </div>
      </div>
    );
  }

  if (!data) return null;

  const unit = data.stockUnit || data.defaultUnit || "";
  const unitLabel = unit ? unit.toUpperCase() : "";
  const stockStatus = data.currentStock < 0
    ? "critical"
    : data.currentStock === 0
    ? "out_of_stock"
    : data.reorderLevel && data.currentStock <= data.reorderLevel
    ? "low"
    : "ok";

  return (
    <div className="flex flex-col min-h-full">
      <AppBar
        title={data.name}
        leading={
          <button onClick={() => navigate(-1)} className="p-1.5 -ml-1.5 rounded-xl hover:bg-black/5">
            <LuArrowLeft size={22} />
          </button>
        }
        actions={[
          <button
            key="catalog"
            onClick={() => navigate(`/catalog/item/${itemId}`)}
            className="flex items-center gap-1.5 h-9 px-3 rounded-xl bg-brand-accent/10 text-brand-accent text-[13px] font-bold hover:bg-brand-accent/20 active:scale-[0.97] transition-all"
          >
            <LuExternalLink size={14} />
            <span className="hidden sm:inline">Catalog</span>
          </button>,
        ]}
      />

      <div className="flex-1 px-4 pb-6 space-y-3 overflow-y-auto">
        {/* Stock card */}
        <Card padding="md">
          <div className="flex items-center justify-between mb-1">
            <p className="text-[13px] font-bold text-text-muted">Current Stock</p>
            <StockStatusBadge status={stockStatus} />
          </div>
          <p className="text-[28px] font-extrabold text-brand-primary tracking-tight">
            {data.currentStock}{" "}
            <span className="text-[14px] font-bold text-text-muted">{unitLabel}</span>
          </p>
          {data.reorderLevel != null && (
            <p className="text-[12px] font-semibold text-text-muted mt-0.5">
              Reorder at {data.reorderLevel} {unitLabel}
            </p>
          )}
        </Card>

        {/* Item info */}
        <Card padding="md">
          <h3 className="text-[13px] font-bold text-text-muted mb-2">Item Info</h3>
          <div className="space-y-1.5">
            {data.itemCode && (
              <div className="flex justify-between">
                <span className="text-[12px] font-semibold text-text-muted">Code</span>
                <span className="text-[12px] font-bold text-text-primary">{data.itemCode}</span>
              </div>
            )}
            {data.barcode && (
              <div className="flex justify-between">
                <span className="text-[12px] font-semibold text-text-muted">Barcode</span>
                <span className="text-[12px] font-bold text-text-primary">{data.barcode}</span>
              </div>
            )}
            {data.categoryName && (
              <div className="flex justify-between">
                <span className="text-[12px] font-semibold text-text-muted">Category</span>
                <span className="text-[12px] font-bold text-text-primary">{data.categoryName}</span>
              </div>
            )}
            {data.typeName && (
              <div className="flex justify-between">
                <span className="text-[12px] font-semibold text-text-muted">Subcategory</span>
                <span className="text-[12px] font-bold text-text-primary">{data.typeName}</span>
              </div>
            )}
            {data.hsnCode && (
              <div className="flex justify-between">
                <span className="text-[12px] font-semibold text-text-muted">HSN</span>
                <span className="text-[12px] font-bold text-text-primary">{data.hsnCode}</span>
              </div>
            )}
            {data.packageType && (
              <div className="flex justify-between">
                <span className="text-[12px] font-semibold text-text-muted">Package</span>
                <span className="text-[12px] font-bold text-text-primary">{data.packageType}</span>
              </div>
            )}
          </div>
        </Card>

        {/* Location & Opening */}
        <Card padding="md">
          <h3 className="text-[13px] font-bold text-text-muted mb-2">Location</h3>
          <div className="space-y-1.5">
            {data.rackLocation && (
              <div className="flex justify-between">
                <span className="text-[12px] font-semibold text-text-muted">Rack</span>
                <span className="text-[12px] font-bold text-text-primary">{data.rackLocation}</span>
              </div>
            )}
            {data.openingStock != null && (
              <div className="flex justify-between">
                <span className="text-[12px] font-semibold text-text-muted">Opening Stock</span>
                <span className="text-[12px] font-bold text-text-primary">
                  {data.openingStock} {unitLabel}
                  {data.openingStockLocked && " (locked)"}
                </span>
              </div>
            )}
          </div>
        </Card>

        {/* Pricing */}
        {(data.defaultLandingCost != null || data.defaultSellingCost != null || data.lastPurchasePrice != null) && (
          <Card padding="md">
            <h3 className="text-[13px] font-bold text-text-muted mb-2">Pricing</h3>
            <div className="space-y-1.5">
              {data.defaultLandingCost != null && (
                <div className="flex justify-between">
                  <span className="text-[12px] font-semibold text-text-muted">Landing Cost</span>
                  <span className="text-[12px] font-bold text-text-primary">
                    ₹{data.defaultLandingCost.toFixed(2)}
                  </span>
                </div>
              )}
              {data.defaultSellingCost != null && (
                <div className="flex justify-between">
                  <span className="text-[12px] font-semibold text-text-muted">Selling Cost</span>
                  <span className="text-[12px] font-bold text-text-primary">
                    ₹{data.defaultSellingCost.toFixed(2)}
                  </span>
                </div>
              )}
              {data.lastPurchasePrice != null && (
                <div className="flex justify-between">
                  <span className="text-[12px] font-semibold text-text-muted">Last Purchase</span>
                  <span className="text-[12px] font-bold text-text-primary">
                    ₹{data.lastPurchasePrice.toFixed(2)}
                  </span>
                </div>
              )}
            </div>
          </Card>
        )}

        {/* Last updated */}
        <Card padding="md">
          <h3 className="text-[13px] font-bold text-text-muted mb-2">Activity</h3>
          <div className="space-y-1.5">
            {data.lastStockUpdatedAt && (
              <div className="flex justify-between">
                <span className="text-[12px] font-semibold text-text-muted">Last Stock Update</span>
                <span className="text-[12px] font-bold text-text-primary">
                  {new Date(data.lastStockUpdatedAt).toLocaleDateString()}
                </span>
              </div>
            )}
            {data.lastPurchaseDate && (
              <div className="flex justify-between">
                <span className="text-[12px] font-semibold text-text-muted">Last Purchase</span>
                <span className="text-[12px] font-bold text-text-primary">
                  {new Date(data.lastPurchaseDate).toLocaleDateString()}
                </span>
              </div>
            )}
            {data.lastSupplierName && (
              <div className="flex justify-between">
                <span className="text-[12px] font-semibold text-text-muted">Last Supplier</span>
                <span className="text-[12px] font-bold text-text-primary">{data.lastSupplierName}</span>
              </div>
            )}
            {data.lastBrokerName && (
              <div className="flex justify-between">
                <span className="text-[12px] font-semibold text-text-muted">Last Broker</span>
                <span className="text-[12px] font-bold text-text-primary">{data.lastBrokerName}</span>
              </div>
            )}
            {data.lastSellingRate != null && (
              <div className="flex justify-between">
                <span className="text-[12px] font-semibold text-text-muted">Last Selling Rate</span>
                <span className="text-[12px] font-bold text-text-primary">₹{data.lastSellingRate.toFixed(2)}</span>
              </div>
            )}
            <div className="flex justify-between">
              <span className="text-[12px] font-semibold text-text-muted">Version</span>
              <span className="text-[12px] font-bold text-text-muted">v{data.stockVersion}</span>
            </div>
          </div>
        </Card>

        {/* Action button */}
        {!showForm ? (
          <Button onClick={() => { setNewQty(String(data.currentStock)); setShowForm(true); }}>
            <LuPenLine size={16} />
            Adjust Stock
          </Button>
        ) : (
          <Card padding="md" className="space-y-3">
            <h3 className="text-[13px] font-bold text-text-muted">Update Stock</h3>

            <div>
              <p className="text-[12px] font-semibold text-text-muted mb-1">Current stock</p>
              <p className="text-[20px] font-extrabold text-brand-primary">
                {data.currentStock} {unitLabel}
              </p>
            </div>

            <Input
              label="New quantity"
              type="number"
              step="any"
              min="0"
              value={newQty}
              onChange={(e) => { setNewQty(e.target.value); setQtyError(null); }}
              error={qtyError || undefined}
            />

            <div>
              <label className="text-[12px] font-bold text-text-primary block mb-1.5">
                Adjustment type
              </label>
              <select
                value={adjustmentType}
                onChange={(e) => setAdjustmentType(e.target.value)}
                className="w-full rounded-xl border border-input-border px-3.5 py-[13px] text-[15px] font-medium text-input-text bg-white focus:outline-none focus:border-brand-accent focus:ring-2 focus:ring-brand-accent/20"
              >
                {ADJUSTMENT_TYPES.map((t) => (
                  <option key={t} value={t}>{t}</option>
                ))}
              </select>
            </div>

            <div>
              <label className="text-[12px] font-bold text-text-primary block mb-1">
                Reason (optional)
              </label>
              <textarea
                value={reason}
                onChange={(e) => setReason(e.target.value)}
                rows={2}
                className="w-full rounded-xl border border-input-border px-3.5 py-2.5 text-[13px] font-medium text-input-text placeholder:text-input-hint focus:outline-none focus:border-brand-accent focus:ring-2 focus:ring-brand-accent/20 resize-none"
                placeholder="Add a note..."
              />
            </div>

            {saveError && (
              <div className="rounded-lg bg-error-tint p-3">
                <p className="text-[13px] font-semibold text-loss">{saveError}</p>
              </div>
            )}

            <div className="flex gap-3">
              <Button variant="secondary" onClick={() => { setShowForm(false); setSaveError(null); setQtyError(null); }}>
                Cancel
              </Button>
              <Button onClick={handleSave} loading={saving} disabled={!canSave}>
                Save
              </Button>
            </div>
          </Card>
        )}
      </div>
    </div>
  );
}
