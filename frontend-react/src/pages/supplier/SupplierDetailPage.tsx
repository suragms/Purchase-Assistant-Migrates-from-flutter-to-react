"use client";

import { useParams, useNavigate } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { LuArrowLeft, LuBookOpen, LuPhone, LuMapPin, LuBuilding } from "react-icons/lu";
import { useAuthStore } from "../../lib/stores/auth-store";
import { getSupplier } from "../../lib/api/contacts";
import { Card } from "../../components/ui/Card";
import { Button } from "../../components/ui/Button";
import { Skeleton } from "../../components/ui/Skeleton";

export default function SupplierDetailPage() {
  const { supplierId } = useParams<{ supplierId: string }>();
  const navigate = useNavigate();
  const businessId = useAuthStore((s) => s.businessId);

  const { data: supplier, isLoading } = useQuery({
    queryKey: ["supplier-detail", businessId, supplierId],
    queryFn: () => getSupplier(businessId!, supplierId!),
    enabled: !!businessId && !!supplierId,
  });

  return (
    <div className="min-h-screen bg-brand-background">
      {/* Header */}
      <div className="sticky top-0 z-10 bg-brand-background border-b border-[rgba(215,231,227,0.42)]">
        <div className="flex items-center gap-3 px-4 py-3">
          <button
            onClick={() => navigate(-1)}
            className="p-2 -ml-2 rounded-xl hover:bg-brand-primary/10 text-brand-primary"
          >
            <LuArrowLeft size={20} />
          </button>
          <div className="flex-1 min-w-0">
            <h1 className="text-lg font-bold text-text-primary truncate">
              {isLoading ? "Supplier" : supplier?.name || "Supplier"}
            </h1>
          </div>
        </div>
      </div>

      <div className="px-4 py-4 space-y-4">
        {isLoading ? (
          <>
            <Skeleton className="h-32 rounded-card" />
            <Skeleton className="h-16 rounded-card" />
          </>
        ) : supplier ? (
          <>
            {/* Contact Info Card */}
            <Card padding="lg">
              <div className="space-y-3">
                {supplier.phone && (
                  <div className="flex items-center gap-3">
                    <div className="w-8 h-8 rounded-full bg-brand-primary/10 flex items-center justify-center">
                      <LuPhone size={14} className="text-brand-primary" />
                    </div>
                    <div>
                      <p className="text-xs text-text-muted">Phone</p>
                      <p className="text-sm font-medium text-text-primary">{supplier.phone}</p>
                    </div>
                  </div>
                )}
                {supplier.address && (
                  <div className="flex items-center gap-3">
                    <div className="w-8 h-8 rounded-full bg-brand-primary/10 flex items-center justify-center">
                      <LuMapPin size={14} className="text-brand-primary" />
                    </div>
                    <div>
                      <p className="text-xs text-text-muted">Address</p>
                      <p className="text-sm font-medium text-text-primary">{supplier.address}</p>
                    </div>
                  </div>
                )}
                {supplier.gst_number && (
                  <div className="flex items-center gap-3">
                    <div className="w-8 h-8 rounded-full bg-brand-primary/10 flex items-center justify-center">
                      <LuBuilding size={14} className="text-brand-primary" />
                    </div>
                    <div>
                      <p className="text-xs text-text-muted">GST Number</p>
                      <p className="text-sm font-medium text-text-primary">{supplier.gst_number}</p>
                    </div>
                  </div>
                )}
              </div>
            </Card>

            {/* View Ledger Button */}
            <Button
              variant="secondary"
              className="w-full"
              onClick={() => navigate(`/supplier/${supplierId}/ledger`)}
            >
              <LuBookOpen className="mr-2" size={18} />
              View Ledger
            </Button>
          </>
        ) : (
          <Card padding="lg" className="text-center text-text-muted">
            Supplier not found
          </Card>
        )}
      </div>
    </div>
  );
}
