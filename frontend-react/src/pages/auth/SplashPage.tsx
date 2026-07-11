import { useEffect, useState, useRef } from "react";
import { useNavigate } from "react-router-dom";
import { useAuthStore } from "../../lib/stores/auth-store";
import { tryRestoreSession } from "../../features/auth/session-restore";

export default function SplashPage() {
  const navigate = useNavigate();
  const { isStaff } = useAuthStore();
  const [error, setError] = useState<string | null>(null);
  const warmupRetried = useRef(false);

  useEffect(() => {
    let cancelled = false;
    async function boot() {
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), 8000);

      try {
        const result = await tryRestoreSession();
        clearTimeout(timeoutId);
        if (cancelled) return;

        if (result.session) {
          navigate(isStaff ? "/staff/home" : "/home", { replace: true });
        } else if (result.error === "expired") {
          navigate("/login?notice=session_expired", { replace: true });
        } else if (result.error === "network") {
          if (!warmupRetried.current) {
            warmupRetried.current = true;
            setError("Server is warming up. Retrying in 10 seconds...");
            setTimeout(boot, 10000);
          } else {
            setError("We couldn't refresh your session. Check your connection and tap Retry.");
          }
        } else {
          navigate("/login", { replace: true });
        }
      } catch {
        clearTimeout(timeoutId);
        if (cancelled) return;
        if (!warmupRetried.current) {
          warmupRetried.current = true;
          setError("Server is warming up. Retrying in 10 seconds...");
          setTimeout(boot, 10000);
        } else {
          setError("We couldn't refresh your session. Check your connection and tap Retry.");
        }
      }
    }
    boot();
    return () => { cancelled = true; };
  }, []);

  return (
    <div
      className="min-h-screen flex flex-col items-center justify-center"
      style={{
        background: "linear-gradient(to bottom, #062E28 0%, #0E4F46 50%, #159A8A 100%)",
      }}
    >
      <div className="flex flex-col items-center gap-5">
        <div className="w-24 h-24 rounded-[24px] bg-white/15 border border-white/30 border-solid flex items-center justify-center">
          <img
            src="/assets/images/app_logo.webp"
            alt="Harisree"
            className="w-12 h-12 object-contain"
            onError={(e) => {
              (e.currentTarget as HTMLImageElement).style.display = "none";
            }}
          />
        </div>

        <div className="text-center">
          <h1
            className="text-[26px] font-extrabold tracking-[-0.5px] text-white"
            style={{ letterSpacing: "-0.5px" }}
          >
            Harisree Warehouse
          </h1>
          <p className="text-[13px] font-medium tracking-[1.2px] text-white/70 mt-1">
            Stock · Purchase · Delivery
          </p>
        </div>

        {!error && (
          <div className="w-6 h-6 border-[2.5px] border-white/80 border-t-transparent rounded-full animate-spin" />
        )}

        {error && (
          <div className="flex flex-col items-center gap-4 mt-4 px-8">
            <p className="text-white/80 text-[13px] text-center leading-relaxed">
              {error}
            </p>
            {error.includes("Retry") && (
              <>
                <button
                  onClick={() => {
                    setError(null);
                    window.location.reload();
                  }}
                  className="flex items-center gap-2 h-11 px-5 rounded-[10px] bg-white/20 text-white font-semibold text-[14px] hover:bg-white/30 transition-colors"
                >
                  <svg className="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
                    <polyline points="23 4 23 10 17 10" />
                    <polyline points="1 20 1 14 7 14" />
                    <path d="M3.51 9a9 9 0 0114.85-3.36L23 10M1 14l4.64 4.36A9 9 0 0020.49 15" />
                  </svg>
                  Retry
                </button>
                <button
                  onClick={() => navigate("/login", { replace: true })}
                  className="text-white/60 text-[13px] font-medium hover:text-white/80 transition-colors"
                >
                  Use another account
                </button>
              </>
            )}
          </div>
        )}
      </div>

      <p className="absolute bottom-6 text-white/40 text-[11px] font-medium">
        Harisree Warehouse v1.0
      </p>
    </div>
  );
}
