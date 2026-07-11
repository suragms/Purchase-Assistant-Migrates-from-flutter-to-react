import { type ButtonHTMLAttributes, type ReactNode } from "react";

interface ChipProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  children: ReactNode;
  selected?: boolean;
}

export function Chip({
  children,
  selected = false,
  className,
  ...props
}: ChipProps) {
  return (
    <button
      className={`inline-flex items-center px-2.5 py-1.5 rounded-md text-[13px] font-semibold border transition-colors duration-150 ${
        selected
          ? "bg-[#D8ECE8] border-[#D8ECE8] text-text-primary"
          : "bg-white border-[rgba(215,231,227,0.75)] text-text-primary hover:border-brand-accent/30"
      } ${className || ""}`}
      {...props}
    >
      {children}
    </button>
  );
}
