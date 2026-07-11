"use client";

import { useParams, useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";

export default function PurchaseDetailPage() {
  const params = useParams();
  const { purchaseId } = params as { purchaseId: string };
  const router = useRouter();

  return (
    <div className="p-4">
      <div className="flex justify-end mb-4">
        <Button onClick={() => router.push(`/purchases/${purchaseId}/edit`)}>
          Edit Purchase
        </Button>
      </div>
      <div className="text-text-muted">PurchaseDetailPage</div>
    </div>
  );
}
