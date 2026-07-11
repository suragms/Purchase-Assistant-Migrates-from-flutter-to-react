import { create } from "zustand";
import type { PurchaseStrictBreakdown } from "../api/types";
import { strictFooterBreakdown } from "../utils/calculations";
import { useDraftStore } from "./draft-store";

interface BreakdownState {
  breakdown: PurchaseStrictBreakdown;
  recalculate: () => void;
}

export const useBreakdownStore = create<BreakdownState>((set) => ({
  breakdown: {
    subtotalGross: 0,
    discountTotal: 0,
    taxTotal: 0,
    freight: 0,
    commission: 0,
    grand: 0,
    linesCount: 0,
    itemCount: 0,
  },
  recalculate: () => {
    const draft = useDraftStore.getState().draft;
    set({ breakdown: strictFooterBreakdown(draft) });
  },
}));
