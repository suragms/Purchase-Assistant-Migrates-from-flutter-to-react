"use client";

import { useState, useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { LuArrowLeft } from "react-icons/lu";
import { useAuthStore } from "../../lib/stores/auth-store";
import {
  listBusinesses,
  updateBusinessBranding,
} from "../../lib/api/settings";
import type { BusinessBrandingPatch } from "../../lib/api/types";
import { Card } from "../../components/ui/Card";
import { Button } from "../../components/ui/Button";
import { Input } from "../../components/ui/Input";

export default function BusinessProfilePage() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const { businessId, isOwner } = useAuthStore();

  const { data: businesses } = useQuery({
    queryKey: ["businesses"],
    queryFn: listBusinesses,
  });

  const business = businesses?.find((b) => b.id === businessId);

  const [name, setName] = useState("");
  const [brandingTitle, setBrandingTitle] = useState("");
  const [gstNumber, setGstNumber] = useState("");
  const [phone, setPhone] = useState("");
  const [contactEmail, setContactEmail] = useState("");
  const [address, setAddress] = useState("");

  useEffect(() => {
    if (business) {
      setName(business.name || "");
      setBrandingTitle(business.branding_title || "");
      setGstNumber(business.gst_number || "");
      setPhone(business.phone || "");
      setContactEmail(business.contact_email || "");
      setAddress(business.address || "");
    }
  }, [business]);

  const mutation = useMutation({
    mutationFn: (data: BusinessBrandingPatch) =>
      updateBusinessBranding(businessId!, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["businesses"] });
      navigate(-1);
    },
  });

  const handleSave = () => {
    if (!name.trim()) return;
    if (gstNumber.trim() && gstNumber.trim().length !== 15) return;
    if (phone.trim() && phone.trim().replace(/\D/g, "").length < 10) return;

    mutation.mutate({
      name: name.trim(),
      branding_title: brandingTitle.trim() || null,
      gst_number: gstNumber.trim().toUpperCase() || null,
      phone: phone.trim() || null,
      contact_email: contactEmail.trim() || null,
      address: address.trim() || null,
    });
  };

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
          <h1 className="text-lg font-bold text-text-primary">Business profile</h1>
        </div>
      </div>

      <div className="px-4 py-4 max-w-2xl mx-auto">
        <p className="text-xs text-text-muted mb-4">
          Shown on purchase order PDFs (GSTIN, address, phone, contact email).
        </p>

        <Card padding="md">
          <div className="space-y-4">
            <Input
              label="Registered business name"
              value={name}
              onChange={(e) => setName(e.target.value)}
              readOnly={!isOwner}
              required
            />

            <Input
              label="Order PDF header title"
              placeholder="e.g. HARISREE AGENCY"
              value={brandingTitle}
              onChange={(e) => setBrandingTitle(e.target.value)}
              readOnly={!isOwner}
            />

            <Input
              label="GSTIN (optional)"
              value={gstNumber}
              onChange={(e) => setGstNumber(e.target.value.toUpperCase())}
              readOnly={!isOwner}
              maxLength={15}
              error={
                gstNumber.trim() && gstNumber.trim().length !== 15
                  ? "GSTIN must be 15 characters"
                  : undefined
              }
            />

            <Input
              label="Phone (optional)"
              value={phone}
              onChange={(e) => setPhone(e.target.value)}
              readOnly={!isOwner}
              type="tel"
              error={
                phone.trim() && phone.trim().replace(/\D/g, "").length < 10
                  ? "Enter at least 10 digits"
                  : undefined
              }
            />

            <Input
              label="Contact email (optional)"
              placeholder="For purchase order PDF header"
              value={contactEmail}
              onChange={(e) => setContactEmail(e.target.value)}
              readOnly={!isOwner}
              type="email"
            />

            <div>
              <label className="block text-sm font-medium text-text-primary mb-1.5">
                Address (optional)
              </label>
              <textarea
                value={address}
                onChange={(e) => setAddress(e.target.value)}
                readOnly={!isOwner}
                rows={3}
                className="w-full rounded-xl border border-brand-border bg-brand-surface px-3 py-2.5 text-sm text-text-primary placeholder:text-text-muted focus:border-brand-primary focus:ring-1 focus:ring-brand-primary outline-none resize-none"
              />
            </div>

            {isOwner ? (
              <Button
                onClick={handleSave}
                disabled={
                  mutation.isPending ||
                  !name.trim() ||
                  (!!gstNumber.trim() && gstNumber.trim().length !== 15) ||
                  (!!phone.trim() && phone.trim().replace(/\D/g, "").length < 10)
                }
                className="w-full"
              >
                {mutation.isPending ? "Saving…" : "Save"}
              </Button>
            ) : (
              <p className="text-xs text-red-500">
                Only workspace owners can edit this profile.
              </p>
            )}
          </div>
        </Card>
      </div>
    </div>
  );
}
