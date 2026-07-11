import type { ReactNode } from "react";

interface AuthPageShellProps {
  children: ReactNode;
  maxWidth?: number;
}

export function AuthPageShell({ children, maxWidth = 420 }: AuthPageShellProps) {
  return (
    <div className="relative min-h-screen overflow-hidden">
      <div className="absolute inset-0">
        <div
          className="absolute inset-0 bg-cover bg-center"
          style={{ backgroundImage: "url(/assets/brand/getstarted_bg.webp)" }}
        />
        <div className="absolute inset-0 backdrop-blur-[12px]" />
        <div
          className="absolute inset-0"
          style={{
            background: "linear-gradient(to bottom, rgba(255,255,255,0.35) 0%, rgba(247,249,246,0.75) 100%)",
          }}
        />
      </div>
      <div className="relative z-10 min-h-screen flex items-start justify-center pt-8 pb-6 overflow-y-auto">
        <div className="w-full px-4" style={{ maxWidth }}>
          <div className="flex flex-col items-center gap-3 mb-6">
            <div className="w-[68px] h-[68px] rounded-full bg-white flex items-center justify-center shadow-[0_4px_16px_rgba(0,0,0,0.12)]">
              <div className="w-[68px] h-[68px] rounded-full overflow-hidden flex items-center justify-center">
                <img
                  src="/assets/brand/logo.webp"
                  alt="Harisree"
                  className="w-full h-full object-cover"
                  onError={(e) => {
                    const t = e.currentTarget;
                    t.style.display = "none";
                    const p = t.parentElement!;
                    const s = document.createElement("span");
                    s.style.cssText = "font-size:28px;font-weight:800;color:#0E4F46;display:flex;align-items:center;justify-content:center;height:100%";
                    s.textContent = "H";
                    p.appendChild(s);
                  }}
                />
              </div>
            </div>
            <h2 className="text-[24px] font-extrabold text-brand-primary text-center leading-tight">
              Harisree Agency
            </h2>
            <p className="text-[14px] font-medium text-text-muted text-center">
              Warehouse Management
            </p>
          </div>
          <div className="rounded-[16px] overflow-hidden backdrop-blur-[20px] bg-white/86 border border-white/65 shadow-[0_8px_20px_rgba(0,0,0,0.06)] p-4">
            {children}
          </div>
        </div>
      </div>
    </div>
  );
}
