import { type ReactNode } from "react";

interface RailItem {
  icon: ReactNode;
  selectedIcon: ReactNode;
  label: string;
  value: string;
}

interface NavigationRailProps {
  items: RailItem[];
  value: string;
  onChange: (value: string) => void;
  extended?: boolean;
  className?: string;
}

export function NavigationRail({
  items,
  value,
  onChange,
  extended = false,
  className,
}: NavigationRailProps) {
  return (
    <nav
      className={`flex flex-col gap-1 py-2 ${
        extended ? "w-60 px-3" : "w-14 px-1"
      } ${className || ""}`}
    >
      {items.map((item) => {
        const selected = item.value === value;
        return (
          <button
            key={item.value}
            onClick={() => onChange(item.value)}
            className={`flex items-center gap-3 rounded-xl transition-colors ${
              extended ? "px-3 py-2.5" : "justify-center py-3"
            } ${
              selected
                ? "bg-[rgba(14,79,70,0.12)] text-brand-primary"
                : "text-text-muted hover:bg-black/5"
            }`}
            title={extended ? undefined : item.label}
          >
            <span className="w-6 h-6 flex items-center justify-center">
              {selected ? item.selectedIcon : item.icon}
            </span>
            {extended && (
              <span
                className={`text-[13px] ${
                  selected ? "font-bold" : "font-medium"
                }`}
              >
                {item.label}
              </span>
            )}
          </button>
        );
      })}
    </nav>
  );
}
