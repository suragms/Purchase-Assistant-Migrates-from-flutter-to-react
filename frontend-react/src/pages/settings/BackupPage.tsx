"use client";

import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { useAuthStore } from "../../lib/stores/auth-store";
import {
  downloadStockExcel,
  downloadPurchasesPdf,
  downloadJsonBackup,
  downloadZipBackup,
} from "../../lib/api/settings";
import { Card } from "../../components/ui/Card";
import { Button } from "../../components/ui/Button";
import { LuArrowLeft, LuDownload, LuFileSpreadsheet, LuFileText, LuFileJson, LuFolderArchive } from "react-icons/lu";

function formatTimestamp(ms: number | null): string {
  if (!ms) return "Never on this device";
  return new Date(ms).toLocaleString("en-IN", {
    day: "2-digit",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function getTimestamp(key: string): number | null {
  try {
    const val = localStorage.getItem(key);
    return val ? Number(val) : null;
  } catch {
    return null;
  }
}

function setTimestamp(key: string): void {
  try {
    localStorage.setItem(key, String(Date.now()));
  } catch {
    // ignore
  }
}

function downloadBlob(blob: Blob, filename: string) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

export default function BackupPage() {
  const navigate = useNavigate();
  const { businessId } = useAuthStore();

  const [busyStock, setBusyStock] = useState(false);
  const [busyPdf, setBusyPdf] = useState(false);
  const [busyJson, setBusyJson] = useState(false);
  const [busyZip, setBusyZip] = useState(false);
  const [preset, setPreset] = useState<"month" | "quarter" | "all">("month");

  const [lastStockAt, setLastStockAt] = useState(() =>
    getTimestamp("backup_last_stock_xlsx_at"),
  );
  const [lastPdfAt, setLastPdfAt] = useState(() =>
    getTimestamp("backup_last_purchases_pdf_at"),
  );
  const [lastJsonAt, setLastJsonAt] = useState(() =>
    getTimestamp("backup_last_json_at"),
  );
  const [lastZipAt, setLastZipAt] = useState(() =>
    getTimestamp("backup_last_zip_at"),
  );

  const anyBusy = busyStock || busyPdf || busyJson || busyZip;

  const handleDownloadStock = async () => {
    if (!businessId || anyBusy) return;
    setBusyStock(true);
    try {
      const blob = await downloadStockExcel(businessId);
      const day = new Date().toISOString().slice(0, 10);
      downloadBlob(blob, `stock_inventory_${day}.xlsx`);
      setTimestamp("backup_last_stock_xlsx_at");
      setLastStockAt(Date.now());
    } catch {
      // error handled silently
    } finally {
      setBusyStock(false);
    }
  };

  const handleDownloadPurchasesPdf = async () => {
    if (!businessId || anyBusy) return;
    setBusyPdf(true);
    try {
      const blob = await downloadPurchasesPdf(businessId);
      const now = new Date();
      const fn = `purchases_${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}.pdf`;
      downloadBlob(blob, fn);
      setTimestamp("backup_last_purchases_pdf_at");
      setLastPdfAt(Date.now());
    } catch {
      // error handled silently
    } finally {
      setBusyPdf(false);
    }
  };

  const handleDownloadJson = async () => {
    if (!businessId || anyBusy) return;
    setBusyJson(true);
    try {
      const blob = await downloadJsonBackup(businessId);
      const day = new Date().toISOString().slice(0, 10).replace(/-/g, "");
      downloadBlob(blob, `backup_${day}.json`);
      setTimestamp("backup_last_json_at");
      setLastJsonAt(Date.now());
    } catch {
      // error handled silently
    } finally {
      setBusyJson(false);
    }
  };

  const handleDownloadZip = async () => {
    if (!businessId || anyBusy) return;
    setBusyZip(true);
    try {
      const blob = await downloadZipBackup(businessId, preset);
      const day = new Date().toISOString().slice(0, 10);
      downloadBlob(blob, `purchase_assistant_backup_${day}.zip`);
      setTimestamp("backup_last_zip_at");
      setLastZipAt(Date.now());
    } catch {
      // error handled silently
    } finally {
      setBusyZip(false);
    }
  };

  return (
    <div className="min-h-screen bg-brand-background">
      {/* Header */}
      <div className="sticky top-0 z-10 bg-brand-background border-b border-[rgba(215,231,227,0.42)]">
        <div className="flex items-center gap-3 px-4 py-3">
          <button
            onClick={() => navigate(-1)}
            className="p-2 -ml-2 rounded-xl hover:bg-brand-primary/10 text-brand-primary"
          >
            <LuArrowLeft size={20} />
          </button>
          <h1 className="text-lg font-bold text-text-primary">Export & Backup</h1>
        </div>
      </div>

      <div className="px-4 py-4 space-y-6 max-w-2xl mx-auto">
        <p className="text-sm text-text-muted">
          Download reports for your records. Files download to your browser's
          Downloads folder.
        </p>

        {/* Stock Excel */}
        <Card padding="md">
          <div className="flex items-start gap-3">
            <div className="w-10 h-10 rounded-lg bg-green-100 flex items-center justify-center flex-shrink-0">
              <LuFileSpreadsheet size={20} className="text-green-600" />
            </div>
            <div className="flex-1">
              <p className="font-semibold text-sm text-text-primary">
                Stock inventory (Excel)
              </p>
              <p className="text-xs text-text-muted mt-0.5">
                Last: {formatTimestamp(lastStockAt)}
              </p>
            </div>
          </div>
          <Button
            onClick={handleDownloadStock}
            disabled={anyBusy}
            className="w-full mt-3 gap-1.5"
          >
            {busyStock ? (
              "Preparing…"
            ) : (
              <>
                <LuDownload size={16} />
                Download Stock Excel
              </>
            )}
          </Button>
        </Card>

        {/* Purchases PDF */}
        <Card padding="md">
          <div className="flex items-start gap-3">
            <div className="w-10 h-10 rounded-lg bg-red-100 flex items-center justify-center flex-shrink-0">
              <LuFileText size={20} className="text-red-600" />
            </div>
            <div className="flex-1">
              <p className="font-semibold text-sm text-text-primary">
                Purchases PDF (this month)
              </p>
              <p className="text-xs text-text-muted mt-0.5">
                Last: {formatTimestamp(lastPdfAt)}
              </p>
            </div>
          </div>
          <Button
            onClick={handleDownloadPurchasesPdf}
            disabled={anyBusy}
            variant="outline"
            className="w-full mt-3 gap-1.5"
          >
            {busyPdf ? (
              "Preparing…"
            ) : (
              <>
                <LuDownload size={16} />
                Download Purchases PDF
              </>
            )}
          </Button>
        </Card>

        {/* JSON Backup */}
        <Card padding="md">
          <div className="flex items-start gap-3">
            <div className="w-10 h-10 rounded-lg bg-blue-100 flex items-center justify-center flex-shrink-0">
              <LuFileJson size={20} className="text-blue-600" />
            </div>
            <div className="flex-1">
              <p className="font-semibold text-sm text-text-primary">JSON backup</p>
              <p className="text-xs text-text-muted mt-0.5">
                Catalog, suppliers, 90-day purchases, and stock audit history.
              </p>
              <p className="text-xs text-text-muted mt-0.5">
                Last: {formatTimestamp(lastJsonAt)}
              </p>
            </div>
          </div>
          <Button
            onClick={handleDownloadJson}
            disabled={anyBusy}
            variant="outline"
            className="w-full mt-3 gap-1.5"
          >
            {busyJson ? (
              "Preparing…"
            ) : (
              <>
                <LuDownload size={16} />
                Download JSON backup
              </>
            )}
          </Button>
        </Card>

        {/* ZIP Backup */}
        <Card padding="md">
          <div className="flex items-start gap-3">
            <div className="w-10 h-10 rounded-lg bg-purple-100 flex items-center justify-center flex-shrink-0">
              <LuFolderArchive size={20} className="text-purple-600" />
            </div>
            <div className="flex-1">
              <p className="font-semibold text-sm text-text-primary">
                ZIP — purchases + stock
              </p>
              <p className="text-xs text-text-muted mt-0.5">
                Purchase summary PDF, one PDF per bill, supplier ledger PDFs, and
                stock Excel.
              </p>
              <p className="text-xs text-text-muted mt-0.5">
                Last: {formatTimestamp(lastZipAt)}
              </p>
            </div>
          </div>

          <div className="flex gap-2 mt-3">
            {[
              { value: "month" as const, label: "This month" },
              { value: "quarter" as const, label: "90 days" },
              { value: "all" as const, label: "All" },
            ].map((p) => (
              <button
                key={p.value}
                onClick={() => setPreset(p.value)}
                className={`px-3 py-1.5 rounded-full text-xs font-medium transition-colors ${
                  preset === p.value
                    ? "bg-brand-primary text-white"
                    : "bg-brand-surface border border-brand-border text-text-muted hover:border-brand-primary/40"
                }`}
              >
                {p.label}
              </button>
            ))}
          </div>

          <Button
            onClick={handleDownloadZip}
            disabled={anyBusy}
            variant="outline"
            className="w-full mt-3 gap-1.5"
          >
            {busyZip ? (
              "Preparing…"
            ) : (
              <>
                <LuDownload size={16} />
                Download ZIP backup
              </>
            )}
          </Button>
        </Card>
      </div>
    </div>
  );
}
