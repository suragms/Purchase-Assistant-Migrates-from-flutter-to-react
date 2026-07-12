import { api } from "./client";
import type {
  SupplierRow,
  SupplierDetail,
  SupplierMetrics,
  SupplierLedger,
  BrokerRow,
} from "./types";

export async function listSuppliers(businessId: string): Promise<SupplierRow[]> {
  const res = await api.get(`/businesses/${businessId}/suppliers`);
  return res.data;
}

export async function getSupplier(
  businessId: string,
  supplierId: string,
): Promise<SupplierDetail> {
  const res = await api.get(
    `/businesses/${businessId}/suppliers/${supplierId}`,
  );
  return res.data;
}

export async function getSupplierMetrics(
  businessId: string,
  supplierId: string,
  from: string,
  to: string,
): Promise<SupplierMetrics> {
  const res = await api.get(
    `/businesses/${businessId}/suppliers/${supplierId}/metrics`,
    { params: { from, to } },
  );
  return res.data;
}

export async function getSupplierLedger(
  businessId: string,
  supplierId: string,
): Promise<SupplierLedger> {
  const res = await api.get(
    `/businesses/${businessId}/suppliers/${supplierId}/ledger`,
  );
  return res.data;
}

export async function getSupplierLedgerPdfUrl(
  businessId: string,
  supplierId: string,
): string {
  return `${api.defaults.baseURL}/businesses/${businessId}/suppliers/${supplierId}/ledger/pdf`;
}

export async function listBrokers(businessId: string): Promise<BrokerRow[]> {
  const res = await api.get(`/businesses/${businessId}/brokers`);
  return res.data;
}
