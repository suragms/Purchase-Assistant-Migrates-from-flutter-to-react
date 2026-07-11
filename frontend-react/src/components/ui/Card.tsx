import { type HTMLAttributes, type ReactNode } from "react";

interface CardProps extends HTMLAttributes<HTMLDivElement> {
  children: ReactNode;
  glass?: boolean;
  padding?: "sm" | "md" | "lg";
}

const paddings = {
  sm: "p-3",
  md: "p-4",
  lg: "p-6",
};

export function Card({
  children,
  glass = false,
  padding = "lg",
  className,
  ...props
}: CardProps) {
  if (glass) {
    return (
      <div
        className={`rounded-glass backdrop-blur-[28px] border border-white/60 bg-white/72 shadow-[0_10px_28px_rgba(14,79,70,0.08),0_4px_16px_rgba(0,0,0,0.06)] ${paddings[padding]} ${className || ""}`}
        {...props}
      >
        {children}
      </div>
    );
  }

  return (
    <div
      className={`rounded-card bg-brand-card border border-[rgba(215,231,227,0.42)] shadow-[0_10px_28px_rgba(14,79,70,0.08),0_4px_16px_rgba(0,0,0,0.06)] ${paddings[padding]} ${className || ""}`}
      {...props}
    >
      {children}
    </div>
  );
}
