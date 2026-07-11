import { useState, useEffect, type ReactNode } from "react";
import { Outlet, useNavigate, useLocation } from "react-router-dom";
import {
  MdHome,
  MdInventory2,
  MdQrCodeScanner,
  MdSearch,
  MdLocalShipping,
  MdChecklist,
} from "react-icons/md";
import { OwnerNavRail } from "./OwnerNavRail";
import { OwnerBottomNav } from "./OwnerBottomNav";
import { ShellBanners } from "./ShellBanners";

function useWidth() {
  const [width, setWidth] = useState(window.innerWidth);
  useEffect(() => {
    const onResize = () => setWidth(window.innerWidth);
    window.addEventListener("resize", onResize);
    return () => window.removeEventListener("resize", onResize);
  }, []);
  return width;
}

export function OwnerShell() {
  const width = useWidth();
  const isMobile = width < 600;
  const isDesktop = width >= 1024;

  return (
    <div className="min-h-screen bg-brand-background">
      {!isMobile && (
        <div className="fixed left-0 top-0 bottom-0 z-40 border-r border-[rgba(215,231,227,0.42)] bg-white">
          <OwnerNavRail extended={isDesktop} />
        </div>
      )}
      <div className={`min-h-screen ${!isMobile ? (isDesktop ? "ml-60" : "ml-14") : ""}`}>
        <ShellBanners />
        <main className="max-w-[1180px] mx-auto pb-24">
          <Outlet />
        </main>
      </div>
      {isMobile && <OwnerBottomNav />}
    </div>
  );
}

export function StaffShell() {
  const width = useWidth();
  const isMobile = width < 600;

  return (
    <div className="min-h-screen bg-brand-background">
      <ShellBanners />
      <main className="max-w-[1180px] mx-auto pb-24">
        <Outlet />
      </main>
      {isMobile && (
        <div className="fixed bottom-0 left-0 right-0 z-50 px-3 pb-3">
          <div className="h-[76px] rounded-[20px] bg-white/90 backdrop-blur-[14px] shadow-[0_-8px_32px_rgba(0,0,0,0.26)] flex items-center justify-around px-2.5 text-xs">
            <NavItem label="Home" icon={<MdHome size={20} />} to="/staff/home" />
            <NavItem label="Stock" icon={<MdInventory2 size={20} />} to="/staff/stock" />
            <NavItem label="Scan" icon={<MdQrCodeScanner size={20} />} to="/staff/scan" />
            <NavItem label="Search" icon={<MdSearch size={20} />} to="/staff/search" />
            <NavItem label="Deliveries" icon={<MdLocalShipping size={20} />} to="/staff/deliveries" />
            <NavItem label="Tasks" icon={<MdChecklist size={20} />} to="/staff/tasks" />
          </div>
        </div>
      )}
    </div>
  );
}

function NavItem({ label, icon, to }: { label: string; icon: ReactNode; to: string }) {
  const navigate = useNavigate();
  const location = useLocation();
  const selected = location.pathname === to;

  return (
    <button
      onClick={() => navigate(to)}
      className={`flex flex-col items-center justify-center gap-0.5 px-1 py-1 flex-1 rounded-xl ${
        selected ? "bg-brand-primary/12" : ""
      }`}
    >
      <span className={selected ? "text-brand-primary" : "text-text-muted"}>{icon}</span>
      <span
        className={`text-[10px] leading-none ${
          selected ? "font-extrabold text-brand-primary" : "font-semibold text-text-muted"
        }`}
      >
        {label}
      </span>
    </button>
  );
}
