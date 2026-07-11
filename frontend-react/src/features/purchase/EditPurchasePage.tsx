"use client";

import { useRouter } from "next/navigation";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { useParams } from "next/navigation";
import { useEffect, useState } from "react";
import { TradePurchaseOut, TradePurchaseUpdateIn } from "@/types/trade-purchase";
import { getPurchase, updatePurchase } from "@/api/trade-purchase";
import { PurchaseForm } from "./PurchaseForm";
import { PurchaseLifecycleTimeline } from "./PurchaseLifecycleTimeline";


export function EditPurchasePage() {
  const router = useRouter();
  const params = useParams();
  const { purchaseId } = params as { purchaseId: string };
  const queryClient = useQueryClient();
  const [isReadOnly, setIsReadOnly] = useState(false);

  // Fetch purchase data
  const { data: purchase, isLoading } = useQuery({
    queryKey: ["purchase", purchaseId],
    queryFn: () => getPurchase(purchaseId),
    onSuccess: (data) => {
      // Disable editing if purchase is committed, cancelled, or deleted
      if (data.status === "stock_committed" || data.status === "completed" || 
          data.status === "cancelled" || data.deletedAt) {
        setIsReadOnly(true);
      }
    },
  });

  // Update mutation
  const { mutate: update, isPending } = useMutation({
    mutationFn: (data: TradePurchaseUpdateIn) => updatePurchase(purchaseId, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["purchase", purchaseId] });
      queryClient.invalidateQueries({ queryKey: ["purchases"] });
      router.push(`/purchases/${purchaseId}`);
    },
  });

  if (isLoading) return <div className="p-4">Loading...</div>;
  if (!purchase) return <div className="p-4">Purchase not found</div>;

  return (
    <div className="p-4 space-y-6">
      <h1 className="text-2xl font-bold">Edit Purchase</h1>
      <PurchaseForm
        initialData={purchase}
        onSubmit={update}
        isSubmitting={isPending}
        isReadOnly={isReadOnly}
      />
      <PurchaseLifecycleTimeline purchaseId={purchaseId} />
    </div>
  );
}