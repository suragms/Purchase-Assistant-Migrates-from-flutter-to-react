"use client";

import { useParams, useNavigate } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import {
  LuArrowLeft,
  LuDownload,
  LuPhone,
  LuFileText,
  LuPackage,
  LuBanknote,
  LuAlertTriangle,
} from "react-icons/lu";
import { useAuthStore } from "../../lib/stores/auth-store";
import {
  getSupplier,
  getSupplierLedger,
  getSupplierLedgerPdfUrl,
} from "../../lib/api/contacts";
import { Card } from "../../components/ui/Card";
import { Button } from "../../components/ui/Button";
import { Skeleton } from "../../components/ui/Skeleton";

function formatCurrency(amount: number): string {
  return `₹${amount.toLocaleString("en-IN", { minimumFractionDigits: 0, maximumFractionDigits: 0 })}`;
}

function formatDate(d: string | null): string {
  if (!d) return "—";
  const dt = new Date(d);
  return dt.toLocaleDateString("en-IN", { day: "2-digit", month: "short", year: "numeric" });
}

function StatusBadge({ status }: { status: string }) {
  const colors: Record<string, string> = {
    confirmed: "bg-blue-100 text-blue-800",
    paid: "bg-green-100 text-green-800",
    partially_paid: "bg-amber-100 text-amber-800",
    overdue: "bg-red-100 text-red-800",
    due_soon: "bg-orange-100 text-orange-800",
    draft: "bg-gray-100 text-gray-600",
    cancelled: "bg-gray-100 text-gray-600",
    completed: "bg-green-100 text-green-800",
  };
  const color = colors[status] || "bg-gray-100 text-gray-600";
  return (
    <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium ${color}`}>
      {status.replace(/_/g, " ")}
    </span>
  );
}

export default function SupplierLedgerPage() {
  const { supplierId } = useParams<{ supplierId: string }>();
  const navigate = useNavigate();
  const businessId = useAuthStore((s) => s.businessId);

  const { data: supplier, isLoading: loadingSupplier } = useQuery({
    queryKey: ["supplier-detail", businessId, supplierId],
    queryFn: () => getSupplier(businessId!, supplierId!),
    enabled: !!businessId && !!supplierId,
  });

  const { data: ledger, isLoading: loadingLedger } = useQuery({
    queryKey: ["supplier-ledger", businessId, supplierId],
    queryFn: () => getSupplierLedger(businessId!, supplierId!),
    enabled: !!businessId && !!supplierId,
  });

  const pdfUrl =
    businessId && supplierId ? getSupplierLedgerPdfUrl(businessId, supplierId) : "#";

  const isLoading = loadingSupplier || loadingLedger;

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
          <div className="flex-1 min-w-0">
            <h1 className="text-lg font-bold text-text-primary truncate">
              {loadingSupplier ? "Supplier Ledger" : `Ledger — ${supplier?.name || ""}`}
            </h1>
          </div>
          {supplier?.phone && (
            <a
              href={`tel:${supplier.phone}`}
              className="p-2 rounded-xl hover:bg-brand-primary/10 text-brand-primary"
            >
              <LuPhone size={18} />
            </a>
          )}
          <a
            href={pdfUrl}
            target="_blank"
            rel="noopener noreferrer"
            className="p-2 rounded-xl hover:bg-brand-primary/10 text-brand-primary"
            title="Download PDF"
          >
            <LuDownload size={18} />
          </a>
        </div>
      </div>

      <div className="px-4 py-4 space-y-4">
        {/* Summary Cards */}
        {isLoading ? (
          <div className="grid grid-cols-2 gap-3">
            {[...Array(4)].map((_, i) => (
              <Skeleton key={i} className="h-20 rounded-card" />
            ))}
          </div>
        ) : ledger ? (
          <div className="grid grid-cols-2 gap-3">
            <Card padding="md" className="flex flex-col gap-1">
              <div className="flex items-center gap-2 text-text-muted text-xs font-medium">
                <LuPackage size={14} />
                <span>Total Purchases</span>
              </div>
              <p className="text-xl font-bold text-text-primary">
                {ledger.rows.length}
              </p>
            </Card>
            <Card padding="md" className="flex flex-col gap-1">
              <div className="flex items-center gap-2 text-text-muted text-xs font-medium">
                <LuFileText size={14} />
                <span>Total Amount</span>
              </div>
              <p className="text-xl font-bold text-text-primary">
                {formatCurrency(ledger.total_amount)}
              </p>
            </Card>
            <Card padding="md" className="flex flex-col gap-1">
              <div className="flex items-center gap-2 text-text-muted text-xs font-medium">
                <LuBanknote size={14} />
                <span>Total Paid</span>
              </div>
              <p className="text-xl font-bold text-green-600">
                {formatCurrency(ledger.total_paid)}
              </p>
            </Card>
            <Card padding="md" className="flex flex-col gap-1">
              <div className="flex items-center gap-2 text-text-muted text-xs font-medium">
                <LuAlertTriangle size={14} />
                <span>Outstanding</span>
              </div>
              <p
                className={`text-xl font-bold ${
                  ledger.total_balance > 0 ? "text-red-600" : "text-green-600"
                }`}
              >
                {formatCurrency(ledger.total_balance)}
              </p>
            </Card>
          </div>
        ) : null}

        {/* Ledger Table */}
        {isLoading ? (
          <div className="space-y-3">
            {[...Array(5)].map((_, i) => (
              <Skeleton key={i} className="h-16 rounded-card" />
            ))}
          </div>
        ) : ledger && ledger.rows.length === 0 ? (
          <Card padding="lg" className="flex flex-col items-center justify-center py-12 text-center">
            <LuFileText size={40} className="text-text-muted/40 mb-3" />
            <p className="text-text-muted font-medium">No purchases yet</p>
            <p className="text-text-muted/60 text-sm mt-1">
              Purchases from this supplier will appear here
            </p>
          </Card>
        ) : ledger ? (
          <div className="space-y-3">
            {/* Desktop table header */}
            <div className="hidden md:grid grid-cols-12 gap-2 px-3 py-2 text-xs font-semibold text-text-muted uppercase tracking-wide">
              <div className="col-span-2">Bill</div>
              <div className="col-span-2">Date</div>
              <div className="col-span-2">Status</div>
              <div className="col-span-2 text-right">Total</div>
              <div className="col-span-2 text-right">Paid</div>
              <div className="col-span-2 text-right">Balance</div>
            </div>

            {/* Rows */}
            {ledger.rows.map((row) => (
              <Card
                key={row.purchase_id}
                padding="md"
                className="cursor-pointer hover:shadow-md transition-shadow"
                onClick={() => navigate(`/purchase/detail/${row.purchase_id}`)}
              >
                {/* Mobile layout */}
                <div className="md:hidden">
                  <div className="flex items-center justify-between mb-2">
                    <div className="flex items-center gap-2">
                      <span className="font-bold text-text-primary text-sm">
                        {row.human_id}
                      </span>
                      <StatusBadge status={row.status} />
                    </div>
                    <span className="text-xs text-text-muted">{formatDate(row.purchase_date)}</span>
                  </div>
                  {row.invoice_number && (
                    <p className="text-xs text-text-muted mb-2">
                      Invoice: {row.invoice_number}
                    </p>
                  )}
                  <div className="grid grid-cols-3 gap-2 text-sm">
                    <div>
                      <p className="text-text-muted text-xs">Total</p>
                      <p className="font-semibold text-text-primary">{formatCurrency(row.total_amount)}</p>
                    </div>
                    <div>
                      <p className="text-text-muted text-xs">Paid</p>
                      <p className="font-semibold text-green-600">{formatCurrency(row.paid_amount)}</p>
                    </div>
                    <div>
                      <p className="text-text-muted text-xs">Balance</p>
                      <p
                        className={`font-semibold ${
                          row.balance > 0 ? "text-red-600" : "text-green-600"
                        }`}
                      >
                        {formatCurrency(row.balance)}
                      </p>
                    </div>
                  </div>
                  {row.due_date && (
                    <p className="text-xs text-text-muted mt-2">
                      Due: {formatDate(row.due_date)}
                    </p>
                  )}
                </div>

                {/* Desktop layout */}
                <div className="hidden md:grid grid-cols-12 gap-2 items-center text-sm">
                  <div className="col-span-2 font-semibold text-text-primary">
                    {row.human_id}
                  </div>
                  <div className="col-span-2 text-text-muted">{formatDate(row.purchase_date)}</div>
                  <div className="col-span-2">
                    <StatusBadge status={row.status} />
                  </div>
                  <div className="col-span-2 text-right font-semibold text-text-primary">
                    {formatCurrency(row.total_amount)}
                  </div>
                  <div className="col-span-2 text-right font-semibold text-green-600">
                    {formatCurrency(row.paid_amount)}
                  </div>
                  <div
                    className={`col-span-2 text-right font-semibold ${
                      row.balance > 0 ? "text-red-600" : "text-green-600"
                    }`}
                  >
                    {formatCurrency(row.balance)}
                  </div>
                </div>
              </Card>
            ))}

            {/* Totals row */}
            <Card padding="md" className="bg-brand-primary/5 border-brand-primary/20">
              <div className="md:grid grid-cols-12 gap-2 items-center text-sm font-bold hidden">
                <div className="col-span-2 text-text-primary">TOTAL</div>
                <div className="col-span-2" />
                <div className="col-span-2" />
                <div className="col-span-2 text-right text-text-primary">
                  {formatCurrency(ledger.total_amount)}
                </div>
                <div className="col-span-2 text-right text-green-600">
                  {formatCurrency(ledger.total_paid)}
                </div>
                <div
                  className={`col-span-2 text-right ${
                    ledger.total_balance > 0 ? "text-red-600" : "text-green-600"
                  }`}
                >
                  {formatCurrency(ledger.total_balance)}
                </div>
              </div>
              {/* Mobile totals */}
              <div className="md:hidden grid grid-cols-3 gap-2 text-sm">
                <div>
                  <p className="text-text-muted text-xs">Total</p>
                  <p className="font-bold text-text-primary">{formatCurrency(ledger.total_amount)}</p>
                </div>
                <div>
                  <p className="text-text-muted text-xs">Paid</p>
                  <p className="font-bold text-green-600">{formatCurrency(ledger.total_paid)}</p>
                </div>
                <div>
                  <p className="text-text-muted text-xs">Balance</p>
                  <p
                    className={`font-bold ${
                      ledger.total_balance > 0 ? "text-red-600" : "text-green-600"
                    }`}
                  >
                    {formatCurrency(ledger.total_balance)}
                  </p>
                </div>
              </div>
            </Card>
          </div>
        ) : null}

        {/* PDF Export Button */}
        {!isLoading && ledger && ledger.rows.length > 0 && (
          <a
            href={pdfUrl}
            target="_blank"
            rel="noopener noreferrer"
            className="block"
          >
            <Button variant="secondary" className="w-full">
              <LuDownload className="mr-2" size={18} />
              Export PDF Statement
            </Button>
          </a>
        )}
      </div>
    </div>
  );
}
