import { type ReactNode } from "react";

interface AppBarProps {
  title: string;
  leading?: ReactNode;
  actions?: ReactNode[];
  className?: string;
}

export function AppBar({ title, leading, actions, className }: AppBarProps) {
  return (
    <header
      className={`flex items-center justify-between h-14 px-4 bg-transparent ${className || ""}`}
    >
      <div className="flex items-center gap-4">
        {leading && <span>{leading}</span>}
        <h1 className="text-lg font-extrabold tracking-[-0.35px] text-brand-primary">
          {title}
        </h1>
      </div>
      {actions && actions.length > 0 && (
        <div className="flex items-center gap-1">{actions}</div>
      )}
    </header>
  );
}
