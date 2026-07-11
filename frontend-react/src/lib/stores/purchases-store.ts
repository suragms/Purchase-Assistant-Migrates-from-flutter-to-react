import { create } from "zustand";
import type { SupplierRow, BrokerRow } from "../api/types";
import { api } from "../api/client";
import { useAuthStore } from "./auth-store";

const CACHE_TTL = 3 * 60 * 1000; // 3 minutes

interface PurchaseRow {
  id: string;
  supplierName: string;
  totalAmount: number;
  status: string;
  purchaseDate: string;
  lineItemCount: number;
  createdAt: string;
  [key: string]: unknown;
}

interface PurchasesState {
  rows: PurchaseRow[];
  hasMore: boolean;
  loading: boolean;
  error: string | null;
  filter: string;
  page: number;
  setFilter: (f: string) => void;
  fetch: (reset?: boolean) => Promise<void>;
}

export const usePurchasesStore = create<PurchasesState>((set, get) => ({
  rows: [],
  hasMore: false,
  loading: false,
  error: null,
  filter: "all",
  page: 0,
  setFilter: (filter) => {
    set({ filter, page: 0, rows: [] });
    get().fetch(true);
  },
  fetch: async (reset = false) => {
    const businessId = useAuthStore.getState().businessId;
    if (!businessId) return;
    const { page, loading } = get();
    if (loading) return;
    const nextPage = reset ? 0 : page + 1;
    set({ loading: true, error: null });
    try {
      const res = await api.get(`/businesses/${businessId}/trade-purchases`, {
        params: { page: nextPage, limit: 100, filter: get().filter },
      });
      const data = res.data as { rows: PurchaseRow[]; hasMore: boolean };
      set({
        rows: reset ? data.rows : [...get().rows, ...data.rows],
        hasMore: data.hasMore,
        page: nextPage,
        loading: false,
      });
    } catch (e) {
      set({ loading: false, error: (e as Error).message });
    }
  },
}));

// Parsed version (synchronous derivation)
interface ParsedState {
  purchases: PurchaseRow[];
  updateFromRows: (rows: PurchaseRow[]) => void;
}

export const useParsedPurchasesStore = create<ParsedState>((set) => ({
  purchases: [],
  updateFromRows: (rows) => set({ purchases: [...rows] }),
}));

// Contacts (suppliers + brokers)
interface ContactsState {
  suppliers: SupplierRow[];
  brokers: BrokerRow[];
  suppliersLoading: boolean;
  brokersLoading: boolean;
  suppliersError: string | null;
  brokersError: string | null;
  lastFetched: number;
  fetchSuppliers: () => Promise<void>;
  fetchBrokers: () => Promise<void>;
  refreshIfNeeded: () => Promise<void>;
}

export const useContactsStore = create<ContactsState>((set, get) => ({
  suppliers: [],
  brokers: [],
  suppliersLoading: false,
  brokersLoading: false,
  suppliersError: null,
  brokersError: null,
  lastFetched: 0,
  fetchSuppliers: async () => {
    const businessId = useAuthStore.getState().businessId;
    if (!businessId) return;
    set({ suppliersLoading: true, suppliersError: null });
    try {
      const res = await api.get(`/businesses/${businessId}/suppliers`);
      set({ suppliers: res.data, suppliersLoading: false, lastFetched: Date.now() });
    } catch (e) {
      set({ suppliersLoading: false, suppliersError: (e as Error).message });
    }
  },
  fetchBrokers: async () => {
    const businessId = useAuthStore.getState().businessId;
    if (!businessId) return;
    set({ brokersLoading: true, brokersError: null });
    try {
      const res = await api.get(`/businesses/${businessId}/brokers`);
      set({ brokers: res.data, brokersLoading: false, lastFetched: Date.now() });
    } catch (e) {
      set({ brokersLoading: false, brokersError: (e as Error).message });
    }
  },
  refreshIfNeeded: async () => {
    if (Date.now() - get().lastFetched > CACHE_TTL) {
      await Promise.all([get().fetchSuppliers(), get().fetchBrokers()]);
    }
  },
}));
