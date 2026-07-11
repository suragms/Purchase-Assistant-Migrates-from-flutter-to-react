import { useQueryClient } from "@tanstack/react-query";

export const queryKeys = {
  purchases: {
    all: ["trade-purchases"] as const,
    list: (businessId: string, filter?: string) =>
      ["trade-purchases", "list", businessId, filter] as const,
    detail: (id: string) => ["trade-purchases", "detail", id] as const,
  },
  dashboard: {
    summary: (businessId: string) => ["dashboard", "summary", businessId] as const,
    homeReports: (businessId: string) =>
      ["dashboard", "home-reports", businessId] as const,
  },
  catalog: {
    items: (businessId: string) => ["catalog", "items", businessId] as const,
    item: (id: string) => ["catalog", "item", id] as const,
  },
  contacts: {
    suppliers: (businessId: string) => ["contacts", "suppliers", businessId] as const,
    brokers: (businessId: string) => ["contacts", "brokers", businessId] as const,
  },
  stock: {
    list: (businessId: string) => ["stock", "list", businessId] as const,
    alerts: (businessId: string) => ["stock", "alerts", businessId] as const,
  },
  notifications: {
    all: (businessId: string) => ["notifications", businessId] as const,
  },
};

// Tiered invalidation (matches Flutter's business_aggregates_invalidation.dart pattern)
export function useInvalidate() {
  const qc = useQueryClient();

  function invalidateAll() {
    qc.invalidateQueries();
  }

  function invalidatePurchases(businessId?: string) {
    if (businessId) {
      qc.invalidateQueries({ queryKey: ["trade-purchases", "list", businessId] });
    } else {
      qc.invalidateQueries({ queryKey: ["trade-purchases"] });
    }
  }

  function invalidateDashboard(_businessId: string) {
    qc.invalidateQueries({ queryKey: ["dashboard"] });
  }

  function invalidateContacts(businessId: string) {
    qc.invalidateQueries({ queryKey: ["contacts", "suppliers", businessId] });
    qc.invalidateQueries({ queryKey: ["contacts", "brokers", businessId] });
  }

  return {
    invalidateAll,
    invalidatePurchases,
    invalidateDashboard,
    invalidateContacts,
  };
}
