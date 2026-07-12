"use client";

import { useNavigate } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import {
  LuArrowLeft,
  LuBuilding2,
  LuUsers,
  LuDownload,
  LuHelpCircle,
  LuPackage,
  LuBarcode,
  LuShoppingCart,
  LuHistory,
  LuListChecks,
  LuFolderOpen,
  LuLayers,
  LuLogOut,
  LuUser,
  LuClipboardList,
  LuScan,
  LuAlertTriangle,
} from "react-icons/lu";
import { useAuthStore } from "../../lib/stores/auth-store";
import { listBusinesses } from "../../lib/api/settings";
import { Card } from "../../components/ui/Card";

interface NavTileProps {
  icon: React.ReactNode;
  label: string;
  onClick: () => void;
  badge?: string;
  danger?: boolean;
}

function NavTile({ icon, label, onClick, badge, danger }: NavTileProps) {
  return (
    <button
      onClick={onClick}
      className={`flex items-center gap-3 w-full p-3 rounded-xl transition-colors text-left ${
        danger
          ? "hover:bg-red-50 text-red-600"
          : "hover:bg-brand-primary/5 text-text-primary"
      }`}
    >
      <div
        className={`w-9 h-9 rounded-lg flex items-center justify-center flex-shrink-0 ${
          danger ? "bg-red-100" : "bg-brand-primary/10"
        }`}
      >
        {icon}
      </div>
      <span className="flex-1 text-sm font-medium">{label}</span>
      {badge && (
        <span className="text-xs text-text-muted bg-gray-100 px-2 py-0.5 rounded-full">
          {badge}
        </span>
      )}
    </button>
  );
}

function SectionTitle({ children }: { children: React.ReactNode }) {
  return (
    <h3 className="text-xs font-semibold text-text-muted uppercase tracking-wide px-1 mt-4 mb-2">
      {children}
    </h3>
  );
}

export default function SettingsPage() {
  const navigate = useNavigate();
  const { session, clearSession, isOwner, isStaff, businessId } = useAuthStore();

  const { data: businesses } = useQuery({
    queryKey: ["businesses"],
    queryFn: listBusinesses,
  });

  const business = businesses?.find((b) => b.id === businessId);
  const userName = session?.name || session?.email || "User";
  const roleName = business?.role || session?.primaryBusiness?.role || "";

  const handleLogout = () => {
    clearSession();
    navigate("/login");
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
          <h1 className="text-lg font-bold text-text-primary">Settings</h1>
        </div>
      </div>

      <div className="px-4 py-4 space-y-1 max-w-2xl mx-auto">
        {/* Account Card */}
        <Card padding="md" className="mb-4">
          <div className="flex items-center gap-3">
            <div className="w-11 h-11 rounded-full bg-brand-primary/10 flex items-center justify-center text-brand-primary font-bold text-lg">
              {userName.charAt(0).toUpperCase()}
            </div>
            <div className="flex-1 min-w-0">
              <p className="font-semibold text-text-primary truncate">{userName}</p>
              <p className="text-xs text-text-muted truncate">
                {session?.primaryBusiness?.name}
                {roleName && ` · ${roleName.charAt(0).toUpperCase() + roleName.slice(1)}`}
              </p>
            </div>
          </div>
        </Card>

        {/* Quick Actions (hidden for staff) */}
        {!isStaff && (
          <>
            <SectionTitle>Quick Actions</SectionTitle>
            <Card padding="sm">
              <NavTile
                icon={<LuShoppingCart size={16} className="text-brand-primary" />}
                label="New purchase"
                onClick={() => navigate("/purchase/new")}
              />
              <NavTile
                icon={<LuHistory size={16} className="text-brand-primary" />}
                label="Purchase history"
                onClick={() => navigate("/purchase")}
              />
            </Card>
          </>
        )}

        {/* Business */}
        <SectionTitle>Business</SectionTitle>
        <Card padding="sm">
          <NavTile
            icon={<LuBuilding2 size={16} className="text-brand-primary" />}
            label="Business profile"
            onClick={() => navigate("/settings/business")}
          />
          {!isStaff && (
            <NavTile
              icon={<LuUsers size={16} className="text-brand-primary" />}
              label="Users & roles"
              onClick={() => navigate("/settings/users")}
            />
          )}
        </Card>

        {/* Operations */}
        <SectionTitle>Operations</SectionTitle>
        <Card padding="sm">
          <NavTile
            icon={<LuListChecks size={16} className="text-brand-primary" />}
            label="Reorder list"
            onClick={() => navigate("/stock/reorder")}
          />
          {!isStaff && (
            <NavTile
              icon={<LuClipboardList size={16} className="text-brand-primary" />}
              label="Opening stock setup"
              onClick={() => navigate("/stock/opening-setup")}
            />
          )}
          <NavTile
            icon={<LuBarcode size={16} className="text-brand-primary" />}
            label="Print barcodes"
            onClick={() => navigate("/barcode/bulk-print")}
          />
          <NavTile
            icon={<LuScan size={16} className="text-brand-primary" />}
            label="Scan item"
            onClick={() => navigate("/barcode/scan")}
          />
        </Card>

        {/* Export & Backup (hidden for staff) */}
        {!isStaff && (
          <>
            <SectionTitle>Export & Backup</SectionTitle>
            <Card padding="sm">
              <NavTile
                icon={<LuDownload size={16} className="text-brand-primary" />}
                label="Backup & export"
                onClick={() => navigate("/settings/backup")}
              />
            </Card>
          </>
        )}

        {/* Data */}
        <SectionTitle>Data</SectionTitle>
        <Card padding="sm">
          <NavTile
            icon={<LuHelpCircle size={16} className="text-brand-primary" />}
            label="Help & guide"
            onClick={() => navigate("/settings/help")}
          />
          <NavTile
            icon={<LuUsers size={16} className="text-brand-primary" />}
            label="Suppliers & brokers"
            onClick={() => navigate("/contacts")}
          />
          <NavTile
            icon={<LuFolderOpen size={16} className="text-brand-primary" />}
            label="Categories"
            onClick={() => navigate("/catalog/taxonomy")}
          />
          {!isStaff && (
            <NavTile
              icon={<LuPackage size={16} className="text-brand-primary" />}
              label="Item catalog"
              onClick={() => navigate("/catalog")}
            />
          )}
          {!isStaff && (
            <NavTile
              icon={<LuLayers size={16} className="text-brand-primary" />}
              label="Set reorder levels"
              onClick={() => navigate("/catalog/setup-reorder-levels")}
            />
          )}
          <NavTile
            icon={<LuAlertTriangle size={16} className="text-brand-primary" />}
            label="Missing item codes"
            onClick={() => navigate("/catalog/missing-codes")}
          />
          {isOwner && (
            <NavTile
              icon={<LuClipboardList size={16} className="text-brand-primary" />}
              label="Owner tasks"
              onClick={() => navigate("/operations/owner-tasks")}
            />
          )}
        </Card>

        {/* Account Actions */}
        <SectionTitle>Account</SectionTitle>
        <Card padding="sm">
          <NavTile
            icon={<LuUser size={16} className="text-brand-primary" />}
            label="My profile"
            onClick={() => navigate("/settings/profile")}
          />
          <NavTile
            icon={<LuLogOut size={16} className="text-red-500" />}
            label="Sign out"
            onClick={handleLogout}
            danger
          />
        </Card>

        {/* Version */}
        <p className="text-center text-xs text-text-muted/50 pt-4 pb-8">
          Purchase Assistant v1.0
        </p>
      </div>
    </div>
  );
}
