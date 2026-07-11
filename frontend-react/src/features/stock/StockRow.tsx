import type { StockListItem } from "../../lib/api/stock";
import { StockStatusBadge, getMissingFlags } from "./StockStatusBadge";

interface StockRowProps {
  row: StockListItem;
  onClick: (row: StockListItem) => void;
}

export function StockRow({ row, onClick }: StockRowProps) {
  const { needsVerification, missingBarcode, missingItemCode } =
    getMissingFlags(row);

  const lastUpdated =
    row.lastMovementAt
      ? new Date(row.lastMovementAt).toLocaleDateString("en-IN", {
          day: "numeric",
          month: "short",
          year: "numeric",
        })
      : "—";

  return (
    <button
      onClick={() => onClick(row)}
      className="w-full text-left bg-white rounded-xl p-4 border border-brand-border shadow-[0_2px_8px_rgba(14,79,70,0.06)] hover:shadow-[0_4px_16px_rgba(14,79,70,0.10)] transition-shadow active:scale-[0.995]"
    >
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-1.5 flex-wrap">
            <span className="text-[15px] font-bold text-text-primary">
              {row.name}
            </span>
            {needsVerification && (
              <span
                className="inline-flex items-center justify-center w-5 h-5 rounded-full bg-warning/15 text-warning"
                title="Needs verification"
              >
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  viewBox="0 0 24 24"
                  fill="currentColor"
                  className="w-3 h-3"
                >
                  <path d="M12 22C6.477 22 2 17.523 2 12S6.477 2 12 2s10 4.477 10 10-4.477 10-10 10zm-1-7v2h2v-2h-2zm0-8v6h2V7h-2z" />
                </svg>
              </span>
            )}
            {missingBarcode && (
              <span
                className="inline-flex items-center justify-center w-5 h-5 rounded-full bg-text-muted/10 text-text-muted"
                title="Missing barcode"
              >
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  viewBox="0 0 24 24"
                  fill="currentColor"
                  className="w-3 h-3"
                >
                  <path d="M3 5v14h2V5H3zm4 0v14h4V5H7zm6 0v14h2V5h-2zm6 0v14h2V5h-2z" />
                </svg>
              </span>
            )}
            {missingItemCode && (
              <span
                className="inline-flex items-center justify-center w-5 h-5 rounded-full bg-text-muted/10 text-text-muted"
                title="Missing item code"
              >
                <svg
                  xmlns="http://www.w3.org/2000/svg"
                  viewBox="0 0 24 24"
                  fill="currentColor"
                  className="w-3 h-3"
                >
                  <path d="M21 16l-6-6h-2l6 6H5.5l6-6h-2L3 16H1v4h22v-4h-2z" />
                </svg>
              </span>
            )}
          </div>

          <div className="flex items-center gap-2 mt-1 text-[13px] text-text-muted">
            {row.itemCode && <span>#{row.itemCode}</span>}
            {row.categoryName && (
              <>
                <span className="text-text-muted/40">|</span>
                <span>{row.categoryName}</span>
                {row.typeName && <span> / {row.typeName}</span>}
              </>
            )}
          </div>
        </div>

        <div className="flex flex-col items-end gap-1 shrink-0">
          <span className="text-[17px] font-extrabold text-text-primary">
            {row.currentStock}{" "}
            <span className="text-[13px] font-semibold text-text-muted">
              {row.displayUnit || row.stockUnit || row.defaultUnit || ""}
            </span>
          </span>
          <StockStatusBadge status={row.status} />
        </div>
      </div>

      <div className="flex items-center justify-between mt-2.5 pt-2.5 border-t border-brand-border/50">
        <div className="flex items-center gap-3 text-[12px] text-text-muted">
          {row.reorderLevel != null && (
            <span>
              Reorder: <strong className="text-text-primary">{row.reorderLevel}</strong>
            </span>
          )}
          {row.rackLocation && (
            <span>
              Loc: <strong className="text-text-primary">{row.rackLocation}</strong>
            </span>
          )}
        </div>
        <span className="text-[11px] text-text-muted">
          Updated {lastUpdated}
          {row.lastStockUpdatedBy ? ` by ${row.lastStockUpdatedBy}` : ""}
        </span>
      </div>
    </button>
  );
}
