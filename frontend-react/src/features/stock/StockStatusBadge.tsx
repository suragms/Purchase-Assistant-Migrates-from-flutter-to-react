import type { StockListItem } from "../../lib/api/stock";

const statusConfig: Record<string, { label: string; classes: string }> = {
  ok: {
    label: "OK",
    classes: "bg-profit/12 text-profit border-profit/25",
  },
  low: {
    label: "Low",
    classes: "bg-warning/12 text-warning border-warning/25",
  },
  out_of_stock: {
    label: "Out",
    classes: "bg-loss/12 text-loss border-loss/25",
  },
  critical: {
    label: "Critical",
    classes: "bg-loss/20 text-loss border-loss/40",
  },
};

export function StockStatusBadge({ status }: { status: string }) {
  const cfg = statusConfig[status] ?? {
    label: status,
    classes: "bg-text-muted/10 text-text-muted border-text-muted/20",
  };
  return (
    <span
      className={`inline-flex items-center px-2 py-0.5 rounded-md text-[11px] font-bold border ${cfg.classes}`}
    >
      {cfg.label}
    </span>
  );
}

export function getMissingFlags(row: StockListItem) {
  return {
    missingBarcode: !row.barcode,
    missingItemCode: !row.itemCode,
    needsVerification: row.needsVerification,
  };
}
