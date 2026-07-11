import { create } from "zustand";
import type { CalcTotals } from "../api/types";
import { computePurchaseTotals } from "../utils/calculations";
import { useDraftStore } from "./draft-store";

interface TotalsState {
  totals: CalcTotals;
  recalculate: () => void;
}

export const useTotalsStore = create<TotalsState>((set) => ({
  totals: { qtySum: 0, amountSum: 0 },
  recalculate: () => {
    const draft = useDraftStore.getState().draft;
    set({ totals: computePurchaseTotals(draft) });
  },
}));
