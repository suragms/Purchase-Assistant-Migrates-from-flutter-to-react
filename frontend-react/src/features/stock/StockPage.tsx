import { useState, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { LuSearch, LuPlus, LuX, LuPackage, LuTriangle } from "react-icons/lu";
import { useAuthStore } from "../../lib/stores/auth-store";
import { listStock } from "../../lib/api/stock";
import { StockRow } from "./StockRow";
import { AppBar, Chip, Input, ListSkeleton, Button } from "../../components/ui";

function useDebounce<T>(value: T, delay: number): T {
  const [debounced, setDebounced] = useState(value);
  useEffect(() => {
    const timer = setTimeout(() => setDebounced(value), delay);
    return () => clearTimeout(timer);
  }, [value, delay]);
  return debounced;
}

const STATUS_OPTIONS = [
  { key: "all", label: "All" },
  { key: "low", label: "Low" },
  { key: "out_of_stock", label: "Out" },
  { key: "critical", label: "Critical" },
] as const;

export default function StockPage() {
  const businessId = useAuthStore((s) => s.businessId);
  const navigate = useNavigate();
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState("all");
  const debouncedSearch = useDebounce(search, 300);

  const queryParams: Record<string, string | number | boolean | undefined> = {
    page: 1,
    perPage: 100,
  };

  if (debouncedSearch) queryParams.q = debouncedSearch;
  if (statusFilter === "low") queryParams.lowStock = true;
  if (statusFilter === "out_of_stock" || statusFilter === "critical") {
    queryParams.lowStock = true;
  }

  const { data, isLoading, isError, error, refetch } = useQuery({
    queryKey: ["stock", "list", businessId, debouncedSearch, statusFilter],
    queryFn: () => listStock(businessId!, queryParams as any),
    enabled: !!businessId,
  });

  const filteredItems = data?.items ?? [];
  const hasActiveFilter = statusFilter !== "all" || !!debouncedSearch;

  return (
    <div className="flex flex-col min-h-full">
      {/* Header */}
      <AppBar
        title="Stock"
        actions={[
          <button
            key="add"
            onClick={() => navigate("/stock/opening-setup")}
            className="flex items-center gap-1.5 h-9 px-3 rounded-xl bg-brand-accent text-white text-[13px] font-bold shadow-[0_4px_12px_rgba(21,154,138,0.30)] hover:shadow-[0_6px_16px_rgba(21,154,138,0.40)] active:scale-[0.97] transition-all"
          >
            <LuPlus size={16} />
            <span className="hidden sm:inline">Add / Adjust Stock</span>
          </button>,
        ]}
      />

      {/* Search */}
      <div className="px-4 pb-2">
        <Input
          placeholder="Search by name, code, or barcode..."
          leftIcon={<LuSearch size={18} />}
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          rightIcon={
            search ? (
              <button onClick={() => setSearch("")} className="p-1">
                <LuX size={16} />
              </button>
            ) : undefined
          }
        />
      </div>

      {/* Status chips */}
      <div className="flex items-center gap-2 px-4 pb-3 overflow-x-auto scrollbar-none">
        {STATUS_OPTIONS.map((opt) => (
          <Chip
            key={opt.key}
            selected={statusFilter === opt.key}
            onClick={() => setStatusFilter(opt.key)}
          >
            {opt.label}
          </Chip>
        ))}
      </div>

      {/* Content */}
      <div className="flex-1 px-4 pb-4">
        {isLoading ? (
          <ListSkeleton rows={8} rowHeight={128} />
        ) : isError ? (
          <div className="flex flex-col items-center justify-center py-16 gap-4">
            <LuTriangle size={48} className="text-loss" />
            <p className="text-text-muted text-sm">
              {(error as any)?.message || "Failed to load stock"}
            </p>
            <Button variant="secondary" onClick={() => refetch()}>
              Retry
            </Button>
          </div>
        ) : filteredItems.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 gap-4">
            <LuPackage size={48} className="text-text-muted/40" />
            <p className="text-text-muted font-semibold">No stock items found</p>
            <p className="text-text-muted/60 text-sm">
              {hasActiveFilter
                ? "Try adjusting your search or filters"
                : "Add items to your catalog to get started"}
            </p>
          </div>
        ) : (
          <div className="flex flex-col gap-2.5">
            {filteredItems.map((item) => (
              <StockRow key={item.id} row={item} onClick={(row) => navigate(`/stock/item/${row.id}`)} />
            ))}
          </div>
        )}
      </div>

    </div>
  );
}
