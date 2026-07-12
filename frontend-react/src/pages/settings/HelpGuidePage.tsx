"use client";

import { useState } from "react";
import { useNavigate } from "react-router-dom";
import {
  LuArrowLeft,
  LuChevronRight,
  LuHome,
  LuShoppingCart,
  LuScan,
  LuPackage,
  LuBarcode,
  LuDownload,
  LuUsers,
  LuTruck,
} from "react-icons/lu";
import { Card } from "../../components/ui/Card";
import { Button } from "../../components/ui/Button";

interface GuideItem {
  role: string;
  icon: React.ReactNode;
  title: string;
  body: string;
  actionLabel: string;
  route: string;
}

const guides: GuideItem[] = [
  {
    role: "Owner",
    icon: <LuHome size={18} className="text-brand-primary" />,
    title: "Home dashboard",
    body: "See today's purchases, low stock alerts, pending deliveries, and recent activity.",
    actionLabel: "Go to Home",
    route: "/home",
  },
  {
    role: "Owner",
    icon: <LuShoppingCart size={18} className="text-brand-primary" />,
    title: "Add a purchase",
    body: "Tap + then Add purchase. Choose supplier, add items, qty and price, then preview and save.",
    actionLabel: "New purchase",
    route: "/purchase/new",
  },
  {
    role: "All",
    icon: <LuScan size={18} className="text-brand-primary" />,
    title: "Scan barcode",
    body: "Tap + then Scan barcode or use the quick action. Hold steady over the label.",
    actionLabel: "Open scanner",
    route: "/barcode/scan",
  },
  {
    role: "All",
    icon: <LuPackage size={18} className="text-brand-primary" />,
    title: "Stock update",
    body: "Stock tab, tap a row, update physical count or system stock. Changes save immediately on the list.",
    actionLabel: "Go to Stock",
    route: "/stock",
  },
  {
    role: "Owner",
    icon: <LuBarcode size={18} className="text-brand-primary" />,
    title: "Print barcode labels",
    body: "Tap + then Print labels. Select items, then download or share the PDF.",
    actionLabel: "Print labels",
    route: "/barcode/bulk-print",
  },
  {
    role: "Owner",
    icon: <LuDownload size={18} className="text-brand-primary" />,
    title: "Backup and export",
    body: "Settings then Export & Backup. Download stock Excel, monthly purchases PDF, or ZIP backup.",
    actionLabel: "Export & Backup",
    route: "/settings/backup",
  },
  {
    role: "Owner",
    icon: <LuUsers size={18} className="text-brand-primary" />,
    title: "Add staff user",
    body: "Settings then Users, add name, phone, and role. Staff can scan, receive deliveries, and count stock.",
    actionLabel: "Users",
    route: "/settings/users",
  },
  {
    role: "Staff",
    icon: <LuTruck size={18} className="text-brand-primary" />,
    title: "Receive delivery",
    body: "Staff home, pending delivery, Arrive and verify. Truck and damage fields are optional.",
    actionLabel: "Staff home",
    route: "/staff/receive",
  },
];

export default function HelpGuidePage() {
  const navigate = useNavigate();
  const [expanded, setExpanded] = useState<number | null>(null);

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
          <h1 className="text-lg font-bold text-text-primary">
            How to use this app
          </h1>
        </div>
      </div>

      <div className="px-4 py-4 max-w-2xl mx-auto">
        <h2 className="text-xl font-bold text-text-primary mb-1">
          Warehouse guide
        </h2>
        <p className="text-sm text-text-muted mb-4">
          Plain steps for owners and staff. Tap Try it to open each feature.
        </p>

        <div className="space-y-3">
          {guides.map((g, i) => {
            const isOpen = expanded === i;
            return (
              <Card key={i} padding="md" className="overflow-hidden">
                <button
                  onClick={() => setExpanded(isOpen ? null : i)}
                  className="w-full flex items-center gap-3 text-left"
                >
                  <div className="w-9 h-9 rounded-lg bg-brand-primary/10 flex items-center justify-center flex-shrink-0">
                    {g.icon}
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="font-semibold text-sm text-text-primary">
                      {g.title}
                    </p>
                    <p className="text-[10px] text-text-muted">
                      {g.role}
                    </p>
                  </div>
                  <LuChevronRight
                    size={16}
                    className={`text-text-muted transition-transform ${isOpen ? "rotate-90" : ""}`}
                  />
                </button>
                {isOpen && (
                  <div className="mt-3 pt-3 border-t border-brand-border">
                    <p className="text-sm text-text-primary leading-relaxed mb-3">
                      {g.body}
                    </p>
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => navigate(g.route)}
                      className="gap-1.5"
                    >
                      {g.actionLabel}
                      <LuChevronRight size={14} />
                    </Button>
                  </div>
                )}
              </Card>
            );
          })}
        </div>
      </div>
    </div>
  );
}
