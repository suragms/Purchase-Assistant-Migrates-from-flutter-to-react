import { create } from "zustand";
import type { PurchaseDraft, PurchaseDraftLine } from "../api/types";

function initialDraft(): PurchaseDraft {
  return {
    supplierId: null,
    supplierName: null,
    brokerId: null,
    brokerName: null,
    purchaseDate: new Date().toISOString().slice(0, 10),
    invoiceText: "",
    headerDiscountPercent: null,
    commissionMode: "percent",
    commissionPercent: null,
    commissionMoney: null,
    freightAmount: null,
    freightType: "separate",
    billtyRate: null,
    deliveredRate: null,
    lines: [],
  };
}

interface DraftState {
  draft: PurchaseDraft;
  reset: () => void;
  replaceDraft: (d: PurchaseDraft) => void;
  setPurchaseDate: (d: string) => void;
  setInvoiceText: (t: string) => void;
  setHeaderDiscount: (pct: number | null) => void;
  setSupplier: (id: string, name: string) => void;
  clearSupplier: () => void;
  setBroker: (id: string, name: string) => void;
  clearBroker: () => void;
  setCommissionMode: (m: string) => void;
  setCommissionPercent: (p: number | null) => void;
  setCommissionMoney: (m: number | null) => void;
  setFreightAmount: (a: number | null) => void;
  setFreightType: (t: string) => void;
  setBilltyRate: (r: number | null) => void;
  setDeliveredRate: (r: number | null) => void;
  addOrReplaceLine: (line: PurchaseDraftLine) => void;
  removeLineAt: (idx: number) => void;
  setLines: (lines: PurchaseDraftLine[]) => void;
}

export const useDraftStore = create<DraftState>((set) => ({
  draft: initialDraft(),
  reset: () => set({ draft: initialDraft() }),
  replaceDraft: (d) => set({ draft: d }),
  setPurchaseDate: (d) =>
    set((s) => ({ draft: { ...s.draft, purchaseDate: d } })),
  setInvoiceText: (t) =>
    set((s) => ({ draft: { ...s.draft, invoiceText: t } })),
  setHeaderDiscount: (pct) =>
    set((s) => ({ draft: { ...s.draft, headerDiscountPercent: pct } })),
  setSupplier: (id, name) =>
    set((s) => ({ draft: { ...s.draft, supplierId: id, supplierName: name } })),
  clearSupplier: () =>
    set((s) => ({ draft: { ...s.draft, supplierId: null, supplierName: null } })),
  setBroker: (id, name) =>
    set((s) => ({ draft: { ...s.draft, brokerId: id, brokerName: name } })),
  clearBroker: () =>
    set((s) => ({ draft: { ...s.draft, brokerId: null, brokerName: null } })),
  setCommissionMode: (m) =>
    set((s) => ({ draft: { ...s.draft, commissionMode: m } })),
  setCommissionPercent: (p) =>
    set((s) => ({ draft: { ...s.draft, commissionPercent: p } })),
  setCommissionMoney: (m) =>
    set((s) => ({ draft: { ...s.draft, commissionMoney: m } })),
  setFreightAmount: (a) =>
    set((s) => ({ draft: { ...s.draft, freightAmount: a } })),
  setFreightType: (t) =>
    set((s) => ({ draft: { ...s.draft, freightType: t } })),
  setBilltyRate: (r) =>
    set((s) => ({ draft: { ...s.draft, billtyRate: r } })),
  setDeliveredRate: (r) =>
    set((s) => ({ draft: { ...s.draft, deliveredRate: r } })),
  addOrReplaceLine: (line) =>
    set((s) => {
      const idx = s.draft.lines.findIndex(
        (l) => l.catalogItemId === line.catalogItemId
      );
      const lines =
        idx >= 0
          ? s.draft.lines.map((l, i) => (i === idx ? line : l))
          : [...s.draft.lines, line];
      return { draft: { ...s.draft, lines } };
    }),
  removeLineAt: (idx) =>
    set((s) => ({
      draft: { ...s.draft, lines: s.draft.lines.filter((_, i) => i !== idx) },
    })),
  setLines: (lines) =>
    set((s) => ({ draft: { ...s.draft, lines } })),
}));
