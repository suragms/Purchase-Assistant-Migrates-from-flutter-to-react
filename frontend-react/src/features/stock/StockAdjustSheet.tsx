import { useState, useEffect } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { LuX } from "react-icons/lu";
import { useAuthStore } from "../../lib/stores/auth-store";
import {
  patchStockItem,
  recordPhysicalCount,
  getStockDetail,
  type StockListItem,
  type StockDetailResponse,
} from "../../lib/api/stock";
import { Button, Input } from "../../components/ui";

type Mode = "physical" | "system";

const REASON_CHIPS = [
  { label: "Physical count", type: "verification" },
  { label: "Sale", type: "sale" },
  { label: "Damage", type: "damaged" },
  { label: "Correction", type: "correction" },
  { label: "Wastage", type: "damaged" },
] as const;

interface StockAdjustSheetProps {
  item: StockListItem;
  onClose: () => void;
  onSaved?: () => void;
}

export function StockAdjustSheet({ item, onClose, onSaved }: StockAdjustSheetProps) {
  const businessId = useAuthStore((s) => s.businessId)!;
  const queryClient = useQueryClient();

  const [mode, setMode] = useState<Mode>("physical");
  const [freshItem, setFreshItem] = useState<StockDetailResponse | null>(null);
  const [qty, setQty] = useState("");
  const [reasonType, setReasonType] = useState("verification");
  const [reasonLabel, setReasonLabel] = useState("Physical count");
  const [notes, setNotes] = useState("");
  const [saving, setSaving] = useState(false);
  const [qtyError, setQtyError] = useState<string | null>(null);
  const [reasonError, setReasonError] = useState<string | null>(null);
  const [saveError, setSaveError] = useState<string | null>(null);

  useEffect(() => {
    getStockDetail(businessId, item.id)
      .then(setFreshItem)
      .catch(() => {
        setFreshItem(null);
      });
  }, [businessId, item.id]);

  const currentStock = freshItem?.currentStock ?? item.currentStock;
  const stockVersion = freshItem?.stockVersion ?? item.stockVersion;
  const unit =
    item.displayUnit || item.stockUnit || item.defaultUnit || "piece";

  const seedQty = mode === "physical"
    ? currentStock
    : currentStock;

  useEffect(() => {
    setQty(String(seedQty));
  }, [mode, seedQty]);

  const parsedQty = (() => {
    const t = qty.trim().replace(/,/g, "");
    if (!t) return null;
    const v = parseFloat(t);
    if (isNaN(v) || v < 0) return null;
    return v;
  })();

  const canSave = !saving && parsedQty !== null && (mode === "physical" || (reasonType.length > 0));

  const handleSave = async () => {
    if (!canSave) {
      if (parsedQty === null) setQtyError("Enter a valid quantity");
      if (mode === "system" && !reasonType) setReasonError("Select a reason");
      return;
    }
    setSaving(true);
    setSaveError(null);

    try {
      if (mode === "system") {
        await patchStockItem(businessId, item.id, {
          newQty: parsedQty!,
          adjustmentType: reasonType,
          reason: notes ? `${reasonLabel} — ${notes}` : reasonLabel,
          lastSeenStockVersion: stockVersion,
        });
      } else {
        await recordPhysicalCount(businessId, item.id, {
          countedQty: parsedQty!,
          notes: notes ? `${reasonLabel} — ${notes}` : reasonLabel,
        });
      }
      queryClient.invalidateQueries({ queryKey: ["stock", "list", businessId] });
      onSaved?.();
      onClose();
    } catch (err: any) {
      if (err?.response?.status === 409) {
        setSaveError(
          "Stock was changed by another user. Please close and try again."
        );
      } else {
        setSaveError(
          err?.response?.data?.message || err?.message || "Failed to save"
        );
      }
    } finally {
      setSaving(false);
    }
  };

  const handleModeChange = (newMode: Mode) => {
    setMode(newMode);
    setReasonError(null);
    if (newMode === "physical") {
      setReasonType("verification");
      setReasonLabel("Physical count");
    } else {
      setReasonType("correction");
      setReasonLabel("Correction");
    }
    setQtyError(null);
  };

  return (
    <div className="flex flex-col gap-4">
      {/* Header */}
      <div className="flex items-start justify-between">
        <div className="min-w-0 flex-1">
          <h2 className="text-base font-extrabold text-text-primary truncate">
            {item.name}
          </h2>
          <p className="text-[13px] font-semibold text-text-muted mt-0.5">
            {mode === "physical" ? "Editing: " : "System now: "}
            <span
              className={
                mode === "physical" ? "text-brand-accent" : "text-blue-600"
              }
            >
              {currentStock} {unit.toUpperCase()}
            </span>
          </p>
          {mode === "physical" && (
            <p className="text-[11px] font-semibold text-text-muted">
              System ledger: {currentStock} {unit.toUpperCase()} (unchanged)
            </p>
          )}
          {item.lastStockUpdatedBy && (
            <p className="text-[11px] font-semibold text-text-muted mt-0.5">
              Last system edit: {item.lastStockUpdatedBy}
            </p>
          )}
        </div>
        <button
          onClick={onClose}
          className="p-1.5 rounded-xl hover:bg-black/5 shrink-0"
        >
          <LuX size={20} />
        </button>
      </div>

      {/* Mode toggle */}
      <div>
        <p className="text-[12px] font-semibold text-text-muted mb-1.5">
          {mode === "physical"
            ? "Physical count — warehouse floor qty. Does not change system ledger."
            : "System stock — ERP ledger qty. Owner gets notified when staff edits this."}
        </p>
        <div className="flex rounded-lg border border-brand-border overflow-hidden">
          <button
            onClick={() => handleModeChange("physical")}
            className={`flex-1 py-2 text-[11px] font-bold transition-colors ${
              mode === "physical"
                ? "bg-brand-primary text-white"
                : "bg-brand-primary/8 text-brand-primary"
            }`}
          >
            Physical
          </button>
          <button
            onClick={() => handleModeChange("system")}
            className={`flex-1 py-2 text-[11px] font-bold transition-colors ${
              mode === "system"
                ? "bg-brand-primary text-white"
                : "bg-brand-primary/8 text-brand-primary"
            }`}
          >
            System
          </button>
        </div>
      </div>

      <hr className="border-brand-border" />

      {/* Qty input */}
      <div>
        <label className="text-[12px] font-bold text-text-primary mb-1 block">
          {mode === "system" ? "System stock" : "Physical stock"}
        </label>
        <Input
          type="number"
          step="any"
          min="0"
          value={qty}
          onChange={(e) => {
            setQty(e.target.value);
            setQtyError(null);
          }}
          error={qtyError || undefined}
        />
      </div>

      {/* Reason chips (system only) */}
      {mode === "system" && (
        <div>
          <label className="text-[12px] font-bold text-text-primary mb-1.5 block">
            Reason
          </label>
          <div className="flex flex-wrap gap-1.5">
            {REASON_CHIPS.map((chip) => (
              <button
                key={chip.type + chip.label}
                onClick={() => {
                  setReasonType(chip.type);
                  setReasonLabel(chip.label);
                  setReasonError(null);
                }}
                className={`px-2.5 py-1 rounded-md text-[11px] font-bold border transition-colors ${
                  reasonLabel === chip.label
                    ? "bg-brand-primary/12 border-brand-primary text-brand-primary"
                    : "bg-white border-brand-border text-text-primary hover:border-brand-accent/30"
                }`}
              >
                {chip.label}
              </button>
            ))}
          </div>
          {reasonError && (
            <p className="text-[12px] font-semibold text-loss mt-1">
              {reasonError}
            </p>
          )}
        </div>
      )}

      {/* Notes */}
      <div>
        <label className="text-[12px] font-bold text-text-primary mb-1 block">
          Notes (optional)
        </label>
        <textarea
          value={notes}
          onChange={(e) => setNotes(e.target.value)}
          rows={2}
          className="w-full rounded-xl border border-input-border px-3.5 py-2.5 text-[13px] font-medium text-input-text placeholder:text-input-hint focus:outline-none focus:border-brand-accent focus:ring-2 focus:ring-brand-accent/20 resize-none"
          placeholder="Add a note..."
        />
      </div>

      {/* Save error */}
      {saveError && (
        <div className="rounded-lg bg-error-tint p-3">
          <p className="text-[13px] font-semibold text-loss">{saveError}</p>
        </div>
      )}

      {/* Actions */}
      <div className="flex gap-3">
        <Button variant="secondary" onClick={onClose} className="flex-1">
          Cancel
        </Button>
        <Button
          variant="primary"
          onClick={handleSave}
          loading={saving}
          disabled={!canSave}
          className="flex-1"
        >
          {mode === "system" ? "SAVE SYSTEM STOCK" : "SAVE PHYSICAL COUNT"}
        </Button>
      </div>
    </div>
  );
}
