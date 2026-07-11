import { type ReactNode } from "react";

interface NavItem {
  icon: ReactNode;
  label: string;
  value: string;
}

interface BottomNavProps {
  items: NavItem[];
  value: string;
  onChange: (value: string) => void;
  fab?: ReactNode;
  className?: string;
}

export function BottomNav({
  items,
  value,
  onChange,
  fab,
  className,
}: BottomNavProps) {
  return (
    <nav
      className={`relative flex items-center justify-around h-[76px] px-[10px] bg-white/90 backdrop-blur-[14px] shadow-[0_-8px_32px_rgba(0,0,0,0.26)] rounded-[20px] ${className || ""}`}
    >
      {items.map((item) => {
        const selected = item.value === value;
        return (
          <button
            key={item.value}
            onClick={() => onChange(item.value)}
            className={`flex flex-col items-center justify-center gap-0.5 px-2 py-1 min-w-0 flex-1 rounded-xl transition-colors ${
              selected ? "bg-brand-primary/12" : ""
            }`}
          >
            <span
              className={
                selected ? "text-brand-primary" : "text-text-muted"
              }
            >
              {item.icon}
            </span>
            <span
              className={`text-[10px] leading-none ${
                selected
                  ? "font-extrabold text-brand-primary"
                  : "font-semibold text-text-muted"
              }`}
            >
              {item.label}
            </span>
          </button>
        );
      })}
      {fab && (
        <div className="absolute -top-6 left-1/2 -translate-x-1/2">{fab}</div>
      )}
    </nav>
  );
}

interface FabProps {
  icon: ReactNode;
  onClick?: () => void;
}

export function Fab({ icon, onClick }: FabProps) {
  return (
    <button
      onClick={onClick}
      className="w-12 h-12 rounded-full bg-gradient-to-r from-[#0E4F46] to-[#159A8A] text-white flex items-center justify-center shadow-[0_8px_24px_rgba(14,79,70,0.30)] transition-transform duration-150 hover:scale-105 active:scale-95"
    >
      {icon}
    </button>
  );
}
