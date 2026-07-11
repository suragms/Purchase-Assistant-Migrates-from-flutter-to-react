"use client";

import { useState } from "react";
import { useParams, useNavigate } from "react-router-dom";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { LuArrowLeft, LuTruck, LuPackage, LuAlertTriangle, LuCheckCircle, LuClock, LuImagePlus, LuSave } from "react-icons/lu";
import { Button, Card, Input, Label, Textarea, Badge, Timeline, FileUpload } from "../../components/ui";
import { api } from "../../lib/api";
import { TradePurchaseDeliveryPipelineOut, TradePurchaseOut, TradePurchaseLineOut } from "../../lib/api/types";

// ===== Types =====
type DeliveryLine = TradePurchaseLineOut & {
  receivedQty: number;
  damagedQty: number;
  notes?: string;
  photos: File[];
};

// ===== API Helpers =====
const fetchDeliveryPipeline = async (businessId: string) => {
  const res = await api.get<TradePurchaseDeliveryPipelineOut>(`/v1/businesses/${businessId}/trade-purchases/delivery-pipeline`);
  return res.data;
};

const fetchPurchase = async (businessId: string, purchaseId: string) => {
  const res = await api.get<TradePurchaseOut>(`/v1/businesses/${businessId}/trade-purchases/${purchaseId}`);
  return res.data;
};

const patchDelivery = async (
  businessId: string,
  purchaseId: string,
  payload: {
    lines: Array<{ lineId: string; receivedQty: number; damagedQty: number }>;
    notes?: string;
    photos?: File[];
  }
) => {
  const formData = new FormData();
  formData.append(
    "request",
    new Blob([JSON.stringify({ lines: payload.lines, notes: payload.notes })], { type: "application/json" })
  );
  if (payload.photos) {
    payload.photos.forEach((photo) => formData.append("photos", photo));
  }
  const res = await api.patch<TradePurchaseOut>(
    `/v1/businesses/${businessId}/trade-purchases/${purchaseId}/delivery`,
    formData,
    { headers: { "Content-Type": "multipart/form-data" } }
  );
  return res.data;
};

const commitStock = async (businessId: string, purchaseId: string) => {
  const res = await api.post<TradePurchaseOut>(`/v1/businesses/${businessId}/trade-purchases/${purchaseId}/commit-stock`);
  return res.data;
};

const createDamageReport = async (businessId: string, payload: { purchaseId: string; lines: Array<{ lineId: string; damagedQty: number }>; notes?: string }) => {
  const res = await api.post(`/v1/businesses/${businessId}/damage-reports`, payload);
  return res.data;
};

// ===== Components =====
const DeliveryStatusBadge = ({ status }: { status: string }) => {
  const variants = {
    pending: { color: "bg-gray-100 text-gray-800", icon: LuClock },
    dispatched: { color: "bg-blue-100 text-blue-800", icon: LuTruck },
    in_transit: { color: "bg-blue-100 text-blue-800", icon: LuTruck },
    arrived: { color: "bg-orange-100 text-orange-800", icon: LuPackage },
    staff_verifying: { color: "bg-purple-100 text-purple-800", icon: LuAlertTriangle },
    staff_verified: { color: "bg-green-100 text-green-800", icon: LuCheckCircle },
    stock_committed: { color: "bg-green-100 text-green-800", icon: LuCheckCircle },
  };
  const { color, icon: Icon } = variants[status as keyof typeof variants] || variants.pending;
  return (
    <Badge variant="outline" className={color}>
      <Icon className="mr-1" size={12} /> {status.replace(/_/g, " ")}
    </Badge>
  );
};

const LineItemRow = ({ line, onChange }: { line: DeliveryLine; onChange: (line: DeliveryLine) => void }) => {
  return (
    <div className="grid grid-cols-10 gap-2 py-2 border-b border-gray-100">
      <div className="col-span-3">
        <p className="font-medium">{line.itemName}</p>
        <p className="text-xs text-gray-500">Expected: {line.qty} {line.unit}</p>
      </div>
      <div className="col-span-2">
        <Label htmlFor={`received-${line.id}`}>Received</Label>
        <Input
          id={`received-${line.id}`}
          type="number"
          min={0}
          max={line.qty}
          value={line.receivedQty}
          onChange={(e) => onChange({ ...line, receivedQty: Number(e.target.value) })}
        />
      </div>
      <div className="col-span-2">
        <Label htmlFor={`damaged-${line.id}`}>Damaged</Label>
        <Input
          id={`damaged-${line.id}`}
          type="number"
          min={0}
          max={line.qty}
          value={line.damagedQty}
          onChange={(e) => onChange({ ...line, damagedQty: Number(e.target.value) })}
        />
      </div>
      <div className="col-span-3">
        <FileUpload
          label="Photos"
          multiple
          accept="image/*"
          value={line.photos}
          onChange={(files) => onChange({ ...line, photos: files })}
        />
      </div>
    </div>
  );
};

// ===== Pages =====
export function ReceiveShipmentListPage() {
  const { businessId } = useAuthStore();
  const navigate = useNavigate();
  const { data } = useQuery({
    queryKey: ["delivery-pipeline", businessId],
    queryFn: () => fetchDeliveryPipeline(businessId!),
  });

  const purchases = [
    ...(data?.dispatched || []),
    ...(data?.inTransit || []),
    ...(data?.arrived || []),
  ];

  return (
    <div className="p-4">
      <div className="flex items-center gap-2 mb-4">
        <h1 className="text-xl font-bold">Receive Shipment</h1>
      </div>
      <div className="space-y-3">
        {purchases.map((p) => (
          <Card key={p.id} className="p-3 cursor-pointer hover:bg-gray-50" onClick={() => navigate(`/staff/receive/${p.id}`)}>
            <div className="flex justify-between items-start">
              <div>
                <p className="font-medium">{p.supplierName}</p>
                <p className="text-sm text-gray-500">Expected: {p.purchaseDate}</p>
                <p className="text-sm text-gray-500">Truck: {p.vehicleNumber || "N/A"}</p>
              </div>
              <div className="flex flex-col items-end gap-1">
                <DeliveryStatusBadge status={p.deliveryStatus || "pending"} />
                <p className="text-sm font-bold">₹{p.totalAmount?.toLocaleString()}</p>
              </div>
            </div>
          </Card>
        ))}
      </div>
    </div>
  );
}

export function ReceiveShipmentDetailPage() {
  const { businessId } = useAuthStore();
  const { purchaseId } = useParams();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [notes, setNotes] = useState("");
  const [lines, setLines] = useState<DeliveryLine[]>([]);

  const { data: purchase } = useQuery({
    queryKey: ["purchase-detail", businessId, purchaseId],
    queryFn: () => fetchPurchase(businessId!, purchaseId!),
    onSuccess: (data) => {
      setLines(
        data.lines.map((line) => ({
          ...line,
          receivedQty: line.receivedQty || line.qty,
          damagedQty: line.damagedQty || 0,
          photos: [],
        }))
      );
    },
  });

  const { mutate: patchDeliveryMutate } = useMutation({
    mutationFn: () =>
      patchDelivery(businessId!, purchaseId!, {
        lines: lines.map((line) => ({ lineId: line.id, receivedQty: line.receivedQty, damagedQty: line.damagedQty })),
        notes,
        photos: lines.flatMap((line) => line.photos),
      }),
    onSuccess: () => {
      if (hasDiscrepancies) {
        createDamageReportMutate();
      } else {
        commitStockMutate();
      }
    },
  });

  const { mutate: createDamageReportMutate } = useMutation({
    mutationFn: () =>
      createDamageReport(businessId!, {
        purchaseId: purchaseId!,
        lines: lines.filter((line) => line.damagedQty > 0).map((line) => ({ lineId: line.id, damagedQty: line.damagedQty })),
        notes,
      }),
    onSuccess: () => commitStockMutate(),
  });

  const { mutate: commitStockMutate } = useMutation({
    mutationFn: () => commitStock(businessId!, purchaseId!),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["delivery-pipeline", businessId] });
      queryClient.invalidateQueries({ queryKey: ["purchase-detail", businessId, purchaseId] });
      navigate(`/staff/purchase-history/${purchaseId}`);
    },
  });

  const hasDiscrepancies = lines.some((line) => line.damagedQty > 0);
  const isValid = lines.every((line) => line.receivedQty >= 0 && line.receivedQty <= line.qty);

  return (
    <div className="p-4">
      <div className="flex items-center gap-2 mb-4">
        <Button variant="ghost" size="icon" onClick={() => navigate(-1)}>
          <LuArrowLeft />
        </Button>
        <h1 className="text-xl font-bold">Receive Shipment</h1>
      </div>
      <div className="space-y-4">
        <Card className="p-4">
          <div className="grid grid-cols-2 gap-4">
            <div>
              <p className="font-medium">{purchase?.supplierName}</p>
              <p className="text-sm text-gray-500">PO: {purchase?.humanId}</p>
            </div>
            <div className="text-right">
              <p className="text-sm text-gray-500">Truck: {purchase?.vehicleNumber || "N/A"}</p>
              <p className="text-sm text-gray-500">Driver: {purchase?.deliveredBy || "N/A"}</p>
            </div>
          </div>
        </Card>

        <Card className="p-4">
          <h2 className="font-bold mb-2">Line Items</h2>
          <div className="space-y-2">
            {lines.map((line) => (
              <LineItemRow key={line.id} line={line} onChange={(updatedLine) => {
                setLines(lines.map((l) => (l.id === updatedLine.id ? updatedLine : l)));
              }} />
            ))}
          </div>
        </Card>

        <Card className="p-4">
          <Label htmlFor="notes">Notes</Label>
          <Textarea id="notes" value={notes} onChange={(e) => setNotes(e.target.value)} />
        </Card>

        <div className="flex gap-2">
          <Button variant="outline" onClick={() => navigate(-1)}>
            Cancel
          </Button>
          <Button
            disabled={!isValid}
            onClick={() => patchDeliveryMutate()}
          >
            <LuSave className="mr-2" /> Submit
          </Button>
        </div>
      </div>
    </div>
  );
}

// ===== Main Page =====
export default function ReceiveShipmentPage() {
  const { purchaseId } = useParams();
  return purchaseId ? <ReceiveShipmentDetailPage /> : <ReceiveShipmentListPage />;
}