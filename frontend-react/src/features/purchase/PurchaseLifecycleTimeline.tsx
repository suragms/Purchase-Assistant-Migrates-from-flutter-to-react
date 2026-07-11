"use client";

import { useQuery } from "@tanstack/react-query";
import { getPurchaseLifecycleEvents } from "@/api/trade-purchase";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Timeline } from "@/components/ui/timeline";


type PurchaseLifecycleTimelineProps = {
  purchaseId: string;
};

export function PurchaseLifecycleTimeline({ purchaseId }: PurchaseLifecycleTimelineProps) {
  const { data: events } = useQuery({
    queryKey: ["purchase-lifecycle", purchaseId],
    queryFn: () => getPurchaseLifecycleEvents(purchaseId),
  });

  return (
    <Card>
      <CardHeader>
        <CardTitle>Lifecycle History</CardTitle>
      </CardHeader>
      <CardContent>
        <Timeline
          events={(events || []).map((event) => ({
            id: event.id,
            title: `${event.fromStatus} → ${event.toStatus}`,
            description: event.notes || "No notes",
            timestamp: event.createdAt,
          }))}
        />
      </CardContent>
    </Card>
  );
}