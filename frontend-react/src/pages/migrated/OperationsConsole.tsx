import { useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { api } from "../../lib/api/client";
import { logout } from "../../lib/api/auth";
import { useAuthStore } from "../../lib/stores/auth-store";

type Supplier = { id: string; name: string; phone?: string | null };
type StockItem = { id: string; name: string; currentStock?: number; stockVersion?: number; defaultUnit?: string | null };
type Purchase = {
  id: string;
  humanId: string;
  supplierName: string;
  supplierId: string;
  totalAmount: number;
  deliveryStatus: string;
  status: string;
};
type UserRow = { id: string; name?: string; email: string; role: string; isActive: boolean };

function todayIso() {
  return new Date().toISOString().slice(0, 10);
}

function messageFromError(error: unknown) {
  const e = error as { response?: { data?: { detail?: string; message?: string }; status?: number }; message?: string };
  return e.response?.data?.detail || e.response?.data?.message || e.message || "Action failed";
}

export function OperationsConsole({ pageId }: { pageId: string }) {
  const navigate = useNavigate();
  const { businessId, clearSession } = useAuthStore();
  const [suppliers, setSuppliers] = useState<Supplier[]>([]);
  const [stock, setStock] = useState<StockItem[]>([]);
  const [purchases, setPurchases] = useState<Purchase[]>([]);
  const [users, setUsers] = useState<UserRow[]>([]);
  const [busy, setBusy] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const [supplierName, setSupplierName] = useState("Default Supplier");
  const [itemName, setItemName] = useState("Sample stock item");
  const [qty, setQty] = useState("10");
  const [rate, setRate] = useState("100");
  const [stockQty, setStockQty] = useState("25");
  const [staffName, setStaffName] = useState("Staff User");
  const [staffPhone, setStaffPhone] = useState("9876543210");
  const [staffPassword, setStaffPassword] = useState("123456789");

  const selectedSupplier = suppliers[0];
  const selectedPurchase = purchases[0];
  const selectedStock = stock[0];

  const showPurchase = ["PurchaseHomePage", "PurchaseNewPage", "PurchaseEditPage", "PurchaseDetailPage"].includes(pageId);
  const showReceive = pageId.includes("Receive") || pageId.includes("Deliver") || pageId === "PurchaseDetailPage" || pageId === "PurchaseHomePage";
  const showStock = pageId.includes("Stock") || pageId.includes("LowStock") || pageId.includes("Opening") || pageId.includes("Reorder") || pageId === "HomePage";
  const showSupplier = pageId.includes("Supplier") || pageId === "ContactsPage" || pageId === "PurchaseHomePage";
  const showSettings = pageId.includes("Settings") || pageId.includes("User") || pageId === "HomePage";

  const canRender = businessId && (showPurchase || showReceive || showStock || showSupplier || showSettings);

  async function refresh() {
    if (!businessId) return;
    const [supplierRes, stockRes, purchaseRes, userRes] = await Promise.allSettled([
      api.get<Supplier[]>(`/businesses/${businessId}/suppliers`),
      api.get<{ items: StockItem[] }>(`/businesses/${businessId}/stock/list`, { params: { perPage: 10 } }),
      api.get<{ items: Purchase[] }>(`/businesses/${businessId}/trade-purchases`, { params: { limit: 10, includeLines: true } }),
      api.get<UserRow[]>(`/businesses/${businessId}/users`),
    ]);
    if (supplierRes.status === "fulfilled") setSuppliers(supplierRes.value.data);
    if (stockRes.status === "fulfilled") setStock(stockRes.value.data.items || []);
    if (purchaseRes.status === "fulfilled") setPurchases(purchaseRes.value.data.items || []);
    if (userRes.status === "fulfilled") setUsers(userRes.value.data);
  }

  useEffect(() => {
    refresh().catch(() => undefined);
  }, [businessId]);

  async function run(label: string, action: () => Promise<string | void>) {
    setBusy(label);
    setError(null);
    setNotice(null);
    try {
      const text = await action();
      setNotice(text || `${label} completed`);
      await refresh();
    } catch (err) {
      setError(messageFromError(err));
    } finally {
      setBusy(null);
    }
  }

  async function ensureSupplier() {
    if (!businessId) throw new Error("No active business");
    if (selectedSupplier) return selectedSupplier;
    const res = await api.post<Supplier>(`/businesses/${businessId}/suppliers`, {
      name: supplierName,
      phone: "9999999999",
      location: "Local",
    });
    return res.data;
  }

  async function createPurchase() {
    if (!businessId) return;
    const supplier = await ensureSupplier();
    const body = {
      purchaseDate: todayIso(),
      supplierId: supplier.id,
      brokerId: null,
      invoiceNumber: `INV-${Date.now().toString().slice(-5)}`,
      paymentDays: 0,
      discount: 0,
      commissionPercent: null,
      commissionMode: "percent",
      commissionMoney: null,
      deliveredRate: null,
      billtyRate: null,
      freightAmount: null,
      freightType: "included",
      forceDuplicate: true,
      status: "active",
      lines: [
        {
          catalogItemId: selectedStock?.id || null,
          itemName,
          qty: Number(qty) || 1,
          unit: selectedStock?.defaultUnit || "kg",
          purchaseRate: Number(rate) || 1,
          landingCost: Number(rate) || 1,
          sellingRate: (Number(rate) || 1) + 10,
          sellingCost: null,
          discount: 0,
          taxPercent: 0,
          taxMode: "exclusive",
        },
      ],
    };
    const res = await api.post(`/businesses/${businessId}/trade-purchases`, body, {
      headers: { "Idempotency-Key": `ui-${Date.now()}` },
    });
    return `Created purchase ${res.data.humanId}`;
  }

  async function editPurchase() {
    if (!businessId || !selectedPurchase) throw new Error("Create a purchase first");
    const supplier = await ensureSupplier();
    const body = {
      purchaseDate: todayIso(),
      supplierId: supplier.id,
      brokerId: null,
      invoiceNumber: `EDIT-${Date.now().toString().slice(-5)}`,
      paymentDays: 0,
      discount: 0,
      commissionPercent: null,
      commissionMode: "percent",
      commissionMoney: null,
      deliveredRate: null,
      billtyRate: null,
      freightAmount: null,
      freightType: "included",
      forceDuplicate: true,
      status: "active",
      lines: [
        {
          catalogItemId: selectedStock?.id || null,
          itemName: `${itemName} edited`,
          qty: Number(qty) || 1,
          unit: selectedStock?.defaultUnit || "kg",
          purchaseRate: Number(rate) || 1,
          landingCost: Number(rate) || 1,
          sellingRate: (Number(rate) || 1) + 15,
          taxMode: "exclusive",
        },
      ],
    };
    await api.put(`/businesses/${businessId}/trade-purchases/${selectedPurchase.id}`, body);
    return `Edited purchase ${selectedPurchase.humanId}`;
  }

  async function receiveDelivery() {
    if (!businessId || !selectedPurchase) throw new Error("Create a purchase first");
    await api.post(`/businesses/${businessId}/trade-purchases/${selectedPurchase.id}/dispatch`, {
      dispatchNote: "Received from migrated React console",
      truckNumber: "LOCAL",
      driverContact: "",
      markInTransit: true,
    });
    await api.post(`/businesses/${businessId}/trade-purchases/${selectedPurchase.id}/arrive`, {
      notes: "Arrived",
      truckNumber: "LOCAL",
      driverContact: "",
    });
    const detail = await api.get(`/businesses/${businessId}/trade-purchases/${selectedPurchase.id}`);
    const lines = (detail.data.lines || []).map((line: { id: string; qty: number }) => ({
      lineId: line.id,
      receivedQty: line.qty,
      damagedQty: 0,
      returnQty: 0,
    }));
    await api.post(`/businesses/${businessId}/trade-purchases/${selectedPurchase.id}/verify`, {
      lines,
      notes: "Verified from React",
    });
    await api.post(`/businesses/${businessId}/trade-purchases/${selectedPurchase.id}/commit-stock`);
    return `Received delivery for ${selectedPurchase.humanId}`;
  }

  async function addStock() {
    if (!businessId || !selectedStock) throw new Error("Add a catalog item first from Catalog > Quick add");
    await api.patch(`/businesses/${businessId}/stock/${selectedStock.id}`, {
      newQty: Number(stockQty) || 0,
      adjustmentType: "manual",
      reason: "Added from migrated React stock menu",
      lastSeenStockVersion: selectedStock.stockVersion,
      idempotencyKey: `stock-${Date.now()}`,
    });
    return `Updated stock for ${selectedStock.name}`;
  }

  async function createStaff() {
    if (!businessId) return;
    const res = await api.post(`/businesses/${businessId}/users`, {
      fullName: staffName,
      phone: staffPhone,
      role: "staff",
      password: staffPassword,
      isActive: true,
      notes: "Created from migrated React settings",
    });
    return `Staff created. Login: ${res.data.loginEmail}`;
  }

  function signOut() {
    logout();
    clearSession();
    navigate("/login", { replace: true });
  }

  const purchaseSummary = useMemo(
    () => selectedPurchase ? `${selectedPurchase.humanId} · ${selectedPurchase.supplierName} · ${selectedPurchase.deliveryStatus}` : "No purchase yet",
    [selectedPurchase]
  );

  if (!canRender) return null;

  return (
    <section className="rounded-card border border-brand-border bg-white p-4 shadow-[0_8px_22px_rgba(14,79,70,0.06)]">
      <div className="flex flex-col gap-1">
        <h2 className="text-lg font-extrabold text-text-primary">Working Actions</h2>
        <p className="text-sm text-text-muted">These buttons call the migrated .NET API directly for this workspace.</p>
      </div>

      {notice && <div className="mt-3 rounded-xl bg-success-tint px-3 py-2 text-sm font-semibold text-profit">{notice}</div>}
      {error && <div className="mt-3 rounded-xl bg-error-tint px-3 py-2 text-sm font-semibold text-loss">{error}</div>}

      <div className="mt-4 grid gap-4 lg:grid-cols-2">
        {(showPurchase || showSupplier) && (
          <div className="rounded-xl border border-brand-border p-3">
            <h3 className="text-sm font-bold text-text-primary">Purchase and Supplier</h3>
            <div className="mt-3 grid gap-2 sm:grid-cols-2">
              <input className="rounded-xl border border-input-border px-3 py-2 text-sm" value={supplierName} onChange={(e) => setSupplierName(e.target.value)} placeholder="Supplier name" />
              <input className="rounded-xl border border-input-border px-3 py-2 text-sm" value={itemName} onChange={(e) => setItemName(e.target.value)} placeholder="Item name" />
              <input className="rounded-xl border border-input-border px-3 py-2 text-sm" value={qty} onChange={(e) => setQty(e.target.value)} placeholder="Qty" />
              <input className="rounded-xl border border-input-border px-3 py-2 text-sm" value={rate} onChange={(e) => setRate(e.target.value)} placeholder="Landing cost" />
            </div>
            <p className="mt-2 text-xs font-semibold text-text-muted">Supplier: {selectedSupplier?.name || "will create default"}</p>
            <div className="mt-3 flex flex-wrap gap-2">
              <button className="rounded-xl bg-brand-primary px-3 py-2 text-sm font-bold text-white disabled:opacity-60" disabled={busy !== null} onClick={() => run("Create purchase", createPurchase)}>Create purchase</button>
              <button className="rounded-xl bg-brand-primary px-3 py-2 text-sm font-bold text-white disabled:opacity-60" disabled={busy !== null} onClick={() => run("Edit purchase", editPurchase)}>Edit latest</button>
              <button
                className="rounded-xl border border-brand-border px-3 py-2 text-sm font-bold text-brand-primary"
                onClick={() =>
                  selectedSupplier
                    ? navigate(`/supplier/${selectedSupplier.id}/ledger`)
                    : run("Create supplier", async () => {
                        const supplier = await ensureSupplier();
                        return `Created supplier ${supplier.name}`;
                      })
                }
              >
                Open supplier ledger
              </button>
            </div>
          </div>
        )}

        {showReceive && (
          <div className="rounded-xl border border-brand-border p-3">
            <h3 className="text-sm font-bold text-text-primary">Receive Delivery</h3>
            <p className="mt-2 text-sm text-text-muted">{purchaseSummary}</p>
            <button className="mt-3 rounded-xl bg-brand-primary px-3 py-2 text-sm font-bold text-white disabled:opacity-60" disabled={busy !== null || !selectedPurchase} onClick={() => run("Receive delivery", receiveDelivery)}>Receive delivery</button>
          </div>
        )}

        {showStock && (
          <div className="rounded-xl border border-brand-border p-3">
            <h3 className="text-sm font-bold text-text-primary">Add Stock</h3>
            <p className="mt-2 text-sm text-text-muted">{selectedStock ? selectedStock.name : "No catalog stock item yet"}</p>
            <input className="mt-3 w-full rounded-xl border border-input-border px-3 py-2 text-sm" value={stockQty} onChange={(e) => setStockQty(e.target.value)} placeholder="New stock qty" />
            <div className="mt-3 flex flex-wrap gap-2">
              <button className="rounded-xl bg-brand-primary px-3 py-2 text-sm font-bold text-white disabled:opacity-60" disabled={busy !== null || !selectedStock} onClick={() => run("Add stock", addStock)}>Add stock</button>
              <button className="rounded-xl border border-brand-border px-3 py-2 text-sm font-bold text-brand-primary" onClick={() => navigate("/catalog/quick-add")}>Add catalog item</button>
            </div>
          </div>
        )}

        {showSettings && (
          <div className="rounded-xl border border-brand-border p-3">
            <h3 className="text-sm font-bold text-text-primary">Settings, Staff and Logout</h3>
            <div className="mt-3 grid gap-2 sm:grid-cols-3">
              <input className="rounded-xl border border-input-border px-3 py-2 text-sm" value={staffName} onChange={(e) => setStaffName(e.target.value)} placeholder="Staff name" />
              <input className="rounded-xl border border-input-border px-3 py-2 text-sm" value={staffPhone} onChange={(e) => setStaffPhone(e.target.value)} placeholder="Phone" />
              <input className="rounded-xl border border-input-border px-3 py-2 text-sm" value={staffPassword} onChange={(e) => setStaffPassword(e.target.value)} placeholder="Password" />
            </div>
            <p className="mt-2 text-xs font-semibold text-text-muted">Users loaded: {users.length}</p>
            <div className="mt-3 flex flex-wrap gap-2">
              <button className="rounded-xl bg-brand-primary px-3 py-2 text-sm font-bold text-white disabled:opacity-60" disabled={busy !== null} onClick={() => run("Create staff", createStaff)}>Create staff</button>
              <button className="rounded-xl border border-brand-border px-3 py-2 text-sm font-bold text-brand-primary" onClick={() => navigate("/settings")}>Settings</button>
              <button className="rounded-xl border border-loss/30 px-3 py-2 text-sm font-bold text-loss" onClick={signOut}>Logout</button>
            </div>
          </div>
        )}
      </div>
    </section>
  );
}
