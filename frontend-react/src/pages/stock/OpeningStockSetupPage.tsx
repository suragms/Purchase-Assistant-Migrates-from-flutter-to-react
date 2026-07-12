"use client";

import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import {
  LuArrowLeft,
  LuSearch,
  LuCheck,
  LuX,
  LuPackage,
  LuBarcode,
  LuFileText,
} from "react-icons/lu";
import { useAuthStore } from "../../lib/stores/auth-store";
import {
  getOpeningStockSetup,
  setOpeningStock,
  type OpeningStockParams,
} from "../../lib/api/stock";
import type { OpeningStockSetupItem } from "../../lib/api/types";
import { Card } from "../../components/ui/Card";
import { Button } from "../../components/ui/Button";
import { Input } from "../../components/ui/Input";
import { Skeleton } from "../../components/ui/Skeleton";

function formatQty(qty: number | null, unit: string | null): string {
  if (qty === null || qty === undefined) return "—";
  return `${qty.toLocaleString("en-IN", { minimumFractionDigits: 0, maximumFractionDigits: 2 })}${unit ? " " + unit : ""}`;
}

type FilterStatus = "all" | "pending" | "completed";

export default function OpeningStockSetupPage() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const businessId = useAuthStore((s) => s.businessId);

  const [search, setSearch] = useState("");
  const [filterStatus, setFilterStatus] = useState<FilterStatus>("all");
  const [page, setPage] = useState(1);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [editingItem, setEditingItem] = useState<OpeningStockSetupItem | null>(null);
  const [editQty, setEditQty] = useState("");
  const [editNotes, setEditNotes] = useState("");
  const [editReason, setEditReason] = useState("");
  const [showBulkSheet, setShowBulkSheet] = useState(false);
  const [bulkQty, setBulkQty] = useState("");
  const [bulkNotes, setBulkNotes] = useState("");

  const params: OpeningStockParams = {
    page,
    per_page: 50,
    q: search || undefined,
    status: filterStatus,
  };

  const { data, isLoading } = useQuery({
    queryKey: ["opening-stock-setup", businessId, params],
    queryFn: () => getOpeningStockSetup(businessId!, params),
    enabled: !!businessId,
  });

  const setOpeningMutation = useMutation({
    mutationFn: ({ itemId, qty, notes, reason }: { itemId: string; qty: number; notes?: string; reason?: string }) =>
      setOpeningStock(businessId!, itemId, { qty, notes, reason, override: true }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["opening-stock-setup", businessId] });
      queryClient.invalidateQueries({ queryKey: ["stock-list", businessId] });
      setEditingItem(null);
      setEditQty("");
      setEditNotes("");
      setEditReason("");
    },
  });

  const summary = data?.summary;
  const items = data?.items || [];
  const totalPages = data ? Math.ceil(data.total / data.per_page) : 1;

  const toggleSelect = (id: string) => {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const selectAll = () => {
    if (selectedIds.size === items.length) {
      setSelectedIds(new Set());
    } else {
      setSelectedIds(new Set(items.map((i) => i.id)));
    }
  };

  const openEdit = (item: OpeningStockSetupItem) => {
    setEditingItem(item);
    setEditQty(item.opening_stock_qty?.toString() || "");
    setEditNotes("");
    setEditReason("");
  };

  const saveEdit = () => {
    if (!editingItem || !editQty) return;
    setOpeningMutation.mutate({
      itemId: editingItem.id,
      qty: parseFloat(editQty),
      notes: editNotes || undefined,
      reason: editReason || undefined,
    });
  };

  const saveBulk = () => {
    if (!bulkQty) return;
    const qty = parseFloat(bulkQty);
    const ids = Array.from(selectedIds);
    let completed = 0;
    for (const id of ids) {
      setOpeningMutation.mutate(
        { itemId: id, qty, notes: bulkNotes || undefined },
        {
          onSuccess: () => {
            completed++;
            if (completed === ids.length) {
              setSelectedIds(new Set());
              setShowBulkSheet(false);
              setBulkQty("");
              setBulkNotes("");
            }
          },
        }
      );
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
          <div className="flex-1 min-w-0">
            <h1 className="text-lg font-bold text-text-primary">Opening Stock Setup</h1>
          </div>
          {selectedIds.size > 0 && (
            <Button
              variant="primary"
              size="sm"
              onClick={() => setShowBulkSheet(true)}
            >
              Set ({selectedIds.size})
            </Button>
          )}
        </div>
      </div>

      <div className="px-4 py-4 space-y-4">
        {/* Summary Cards */}
        {isLoading ? (
          <div className="grid grid-cols-3 gap-3">
            {[...Array(3)].map((_, i) => (
              <Skeleton key={i} className="h-16 rounded-card" />
            ))}
          </div>
        ) : summary ? (
          <div className="grid grid-cols-3 gap-3">
            <Card padding="md" className="flex flex-col items-center gap-1">
              <span className="text-2xl font-bold text-amber-600">{summary.pending_count}</span>
              <span className="text-xs text-text-muted">Pending</span>
            </Card>
            <Card padding="md" className="flex flex-col items-center gap-1">
              <span className="text-2xl font-bold text-green-600">{summary.completed_count}</span>
              <span className="text-xs text-text-muted">Completed</span>
            </Card>
            <Card padding="md" className="flex flex-col items-center gap-1">
              <span className="text-2xl font-bold text-brand-primary">{summary.total_count}</span>
              <span className="text-xs text-text-muted">Total</span>
            </Card>
          </div>
        ) : null}

        {/* Search */}
        <div className="relative">
          <LuSearch className="absolute left-3 top-1/2 -translate-y-1/2 text-text-muted" size={16} />
          <Input
            placeholder="Search items..."
            value={search}
            onChange={(e) => {
              setSearch(e.target.value);
              setPage(1);
            }}
            className="pl-9"
          />
        </div>

        {/* Filter Chips */}
        <div className="flex gap-2 overflow-x-auto pb-1">
          {(["all", "pending", "completed"] as FilterStatus[]).map((status) => (
            <button
              key={status}
              onClick={() => {
                setFilterStatus(status);
                setPage(1);
              }}
              className={`px-3 py-1.5 rounded-full text-sm font-medium whitespace-nowrap transition-colors ${
                filterStatus === status
                  ? "bg-brand-primary text-white"
                  : "bg-white border border-input-border text-text-primary hover:bg-gray-50"
              }`}
            >
              {status.charAt(0).toUpperCase() + status.slice(1)}
            </button>
          ))}
        </div>

        {/* Select All */}
        {items.length > 0 && (
          <button
            onClick={selectAll}
            className="flex items-center gap-2 text-sm text-brand-primary font-medium"
          >
            <div
              className={`w-4 h-4 rounded border ${
                selectedIds.size === items.length && items.length > 0
                  ? "bg-brand-primary border-brand-primary"
                  : "border-gray-300"
              } flex items-center justify-center`}
            >
              {selectedIds.size === items.length && items.length > 0 && (
                <LuCheck size={10} className="text-white" />
              )}
            </div>
            {selectedIds.size === items.length ? "Deselect all" : "Select all"}
          </button>
        )}

        {/* Items List */}
        {isLoading ? (
          <div className="space-y-3">
            {[...Array(5)].map((_, i) => (
              <Skeleton key={i} className="h-20 rounded-card" />
            ))}
          </div>
        ) : items.length === 0 ? (
          <Card padding="lg" className="flex flex-col items-center justify-center py-12 text-center">
            <LuPackage size={40} className="text-text-muted/40 mb-3" />
            <p className="text-text-muted font-medium">No items found</p>
            <p className="text-text-muted/60 text-sm mt-1">
              {search ? "Try a different search" : "All items have opening stock set"}
            </p>
          </Card>
        ) : (
          <div className="space-y-2">
            {items.map((item) => (
              <Card
                key={item.id}
                padding="md"
                className={`cursor-pointer transition-colors ${
                  selectedIds.has(item.id) ? "ring-2 ring-brand-primary" : ""
                }`}
                onClick={() => toggleSelect(item.id)}
              >
                <div className="flex items-start gap-3">
                  {/* Checkbox */}
                  <div
                    className={`mt-0.5 w-5 h-5 rounded border flex-shrink-0 flex items-center justify-center ${
                      selectedIds.has(item.id)
                        ? "bg-brand-primary border-brand-primary"
                        : "border-gray-300"
                    }`}
                  >
                    {selectedIds.has(item.id) && <LuCheck size={12} className="text-white" />}
                  </div>

                  {/* Item Info */}
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 mb-1">
                      <p className="font-semibold text-text-primary text-sm truncate">{item.name}</p>
                      {item.setup_status === "completed" && (
                        <span className="inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium bg-green-100 text-green-700">
                          Set
                        </span>
                      )}
                      {item.opening_stock_locked && (
                        <span className="inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-medium bg-blue-100 text-blue-700">
                          Locked
                        </span>
                      )}
                    </div>
                    <div className="flex items-center gap-2 text-xs text-text-muted">
                      {item.item_code && <span>{item.item_code}</span>}
                      {item.category_name && <span>· {item.category_name}</span>}
                      {item.unit && <span>· {item.unit}</span>}
                    </div>
                    <div className="flex items-center gap-3 mt-2 text-xs">
                      <span className="text-text-muted">
                        Stock: <span className="font-medium text-text-primary">{formatQty(item.current_stock, item.unit)}</span>
                      </span>
                      {item.opening_stock_qty !== null && (
                        <span className="text-brand-primary font-medium">
                          Opening: {formatQty(item.opening_stock_qty, item.unit)}
                        </span>
                      )}
                      {item.missing_barcode && (
                        <span className="inline-flex items-center gap-0.5 text-amber-600">
                          <LuBarcode size={10} /> No barcode
                        </span>
                      )}
                    </div>
                  </div>

                  {/* Edit Button */}
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      openEdit(item);
                    }}
                    className="p-2 rounded-lg hover:bg-brand-primary/10 text-brand-primary flex-shrink-0"
                  >
                    <LuFileText size={16} />
                  </button>
                </div>
              </Card>
            ))}
          </div>
        )}

        {/* Pagination */}
        {data && totalPages > 1 && (
          <div className="flex items-center justify-between pt-2">
            <Button
              variant="secondary"
              size="sm"
              disabled={page <= 1}
              onClick={() => setPage((p) => p - 1)}
            >
              Previous
            </Button>
            <span className="text-sm text-text-muted">
              Page {page} of {totalPages}
            </span>
            <Button
              variant="secondary"
              size="sm"
              disabled={page >= totalPages}
              onClick={() => setPage((p) => p + 1)}
            >
              Next
            </Button>
          </div>
        )}
      </div>

      {/* Single Item Edit Modal */}
      {editingItem && (
        <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center">
          <div
            className="absolute inset-0 bg-black/40"
            onClick={() => !setOpeningMutation.isPending && setEditingItem(null)}
          />
          <div className="relative bg-white rounded-t-2xl sm:rounded-2xl w-full sm:max-w-md p-6 space-y-4">
            <div className="flex items-center justify-between">
              <h2 className="text-lg font-bold text-text-primary">Set Opening Stock</h2>
              <button
                onClick={() => !setOpeningMutation.isPending && setEditingItem(null)}
                className="p-1 rounded-lg hover:bg-gray-100"
              >
                <LuX size={18} />
              </button>
            </div>

            <div>
              <p className="font-semibold text-text-primary">{editingItem.name}</p>
              <p className="text-xs text-text-muted">
                Current stock: {formatQty(editingItem.current_stock, editingItem.unit)}
                {editingItem.opening_stock_qty !== null && (
                  <> · Current opening: {formatQty(editingItem.opening_stock_qty, editingItem.unit)}</>
                )}
              </p>
            </div>

            <div>
              <label className="block text-sm font-medium text-text-primary mb-1">
                Opening Quantity
              </label>
              <Input
                type="number"
                min={0}
                value={editQty}
                onChange={(e) => setEditQty(e.target.value)}
                placeholder="Enter quantity"
              />
            </div>

            <div>
              <label className="block text-sm font-medium text-text-primary mb-1">
                Notes (optional)
              </label>
              <Input
                value={editNotes}
                onChange={(e) => setEditNotes(e.target.value)}
                placeholder="Optional notes"
              />
            </div>

            {editingItem.opening_stock_locked && (
              <div>
                <label className="block text-sm font-medium text-text-primary mb-1">
                  Reason (required for locked items)
                </label>
                <Input
                  value={editReason}
                  onChange={(e) => setEditReason(e.target.value)}
                  placeholder="Reason for change"
                />
              </div>
            )}

            <div className="flex gap-3 pt-2">
              <Button
                variant="secondary"
                className="flex-1"
                disabled={setOpeningMutation.isPending}
                onClick={() => setEditingItem(null)}
              >
                Cancel
              </Button>
              <Button
                variant="primary"
                className="flex-1"
                loading={setOpeningMutation.isPending}
                disabled={!editQty || (editingItem.opening_stock_locked && !editReason)}
                onClick={saveEdit}
              >
                Save
              </Button>
            </div>
          </div>
        </div>
      )}

      {/* Bulk Set Modal */}
      {showBulkSheet && (
        <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center">
          <div
            className="absolute inset-0 bg-black/40"
            onClick={() => !setOpeningMutation.isPending && setShowBulkSheet(false)}
          />
          <div className="relative bg-white rounded-t-2xl sm:rounded-2xl w-full sm:max-w-md p-6 space-y-4">
            <div className="flex items-center justify-between">
              <h2 className="text-lg font-bold text-text-primary">
                Set Opening Stock ({selectedIds.size} items)
              </h2>
              <button
                onClick={() => !setOpeningMutation.isPending && setShowBulkSheet(false)}
                className="p-1 rounded-lg hover:bg-gray-100"
              >
                <LuX size={18} />
              </button>
            </div>

            <div>
              <label className="block text-sm font-medium text-text-primary mb-1">
                Opening Quantity
              </label>
              <Input
                type="number"
                min={0}
                value={bulkQty}
                onChange={(e) => setBulkQty(e.target.value)}
                placeholder="Enter quantity for all selected items"
              />
            </div>

            <div>
              <label className="block text-sm font-medium text-text-primary mb-1">
                Notes (optional)
              </label>
              <Input
                value={bulkNotes}
                onChange={(e) => setBulkNotes(e.target.value)}
                placeholder="Optional notes"
              />
            </div>

            <div className="flex gap-3 pt-2">
              <Button
                variant="secondary"
                className="flex-1"
                disabled={setOpeningMutation.isPending}
                onClick={() => setShowBulkSheet(false)}
              >
                Cancel
              </Button>
              <Button
                variant="primary"
                className="flex-1"
                loading={setOpeningMutation.isPending}
                disabled={!bulkQty}
                onClick={saveBulk}
              >
                Save All
              </Button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
