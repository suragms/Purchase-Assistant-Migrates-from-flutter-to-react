import { api } from "./client";
import type { SupplierRow, BrokerRow } from "./types";

export async function listSuppliers(businessId: string): Promise<SupplierRow[]> {
  const res = await api.get(`/businesses/${businessId}/suppliers`);
  return res.data;
}

export async function listBrokers(businessId: string): Promise<BrokerRow[]> {
  const res = await api.get(`/businesses/${businessId}/brokers`);
  return res.data;
}
