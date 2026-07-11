import { useEffect, useState, useRef } from "react";
import { useNavigate } from "react-router-dom";
import { useAuthStore } from "../../../lib/stores/auth-store";
import { tryRestoreSession } from "../session-restore";
import { AUTH_ASSETS } from "../auth-brand-assets";

export function SplashPage() {
  const navigate = useNavigate();
  const { isStaff } = useAuthStore();
  const [status, setStatus] = useState<"loading" | "retrying" | "error" | "done">("loading");
  const [errorMessage, setErrorMessage] = useState("");
  const retried = useRef(false);
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    setVisible(true);
  }, []);

  useEffect(() => {
    let timeoutId: ReturnType<typeof setTimeout>;
    let cancelled = false;

    async function boot() {
      try {
        const result = await tryRestoreSession();
        if (cancelled) return;

        if (result.session) {
          setStatus("done");
          navigate(isStaff ? "/staff/home" : "/home", { replace: true });
          return;
        }

        if (!retried.current) {
          // First attempt timed out or failed — retry once after 10s
          retried.current = true;
          setStatus("retrying");
          // Wait 10s, then try again with promise race
          await new Promise<void>((resolve) => {
            timeoutId = setTimeout(resolve, 10_000);
          });
          if (cancelled) return;

          const retryResult = await tryRestoreSession();
          if (cancelled) return;

          if (retryResult.session) {
            setStatus("done");
            navigate(isStaff ? "/staff/home" : "/home", { replace: true });
            return;
          }

          if (retryResult.error === "expired") {
            navigate("/login?notice=session_expired");
            return;
          }

          setStatus("error");
          setErrorMessage(
            retryResult.errorMessage || "Couldn't refresh your session. Try again."
          );
        } else {
          // Second attempt failed
          if (result.error === "expired") {
            navigate("/login?notice=session_expired");
            return;
          }
          setStatus("error");
          setErrorMessage(
            result.errorMessage || "Couldn't refresh your session. Try again."
          );
        }
      } catch {
        if (!cancelled) {
          setStatus("error");
          setErrorMessage("Couldn't refresh your session. Try again.");
        }
      }
    }

    boot();

    return () => {
      cancelled = true;
      if (timeoutId) clearTimeout(timeoutId);
    };
  }, []);

  async function handleRetry() {
    setStatus("loading");
    setErrorMessage("");
    try {
      const result = await tryRestoreSession();
      if (result.session) {
        setStatus("done");
        navigate(isStaff ? "/staff/home" : "/home", { replace: true });
        return;
      }
      setStatus("error");
      setErrorMessage(result.errorMessage || "Couldn't refresh your session. Try again.");
    } catch {
      setStatus("error");
      setErrorMessage("Couldn't refresh your session. Try again.");
    }
  }

  return (
    <div
      className="min-h-screen flex flex-col items-center justify-center px-6"
      style={{
        background: `linear-gradient(to bottom, #062E28 0%, #0E4F46 50%, #159A8A 100%)`,
      }}
    >
      <div
        className={`flex flex-col items-center transition-all duration-800 ease-out ${
          visible ? "opacity-100" : "opacity-0"
        }`}
      >
        {/* Logo */}
        <div className="w-24 h-24 rounded-[24px] bg-white/15 border border-white/30 border-[1.5px] flex items-center justify-center mb-5 overflow-hidden">
          <img
            src={AUTH_ASSETS.appLogo}
            alt="Harisree"
            className="w-full h-full object-cover rounded-[22px]"
            onError={(e) => {
              const target = e.currentTarget;
              target.style.display = "none";
              (target.parentElement as HTMLElement).innerHTML =
                '<svg width="48" height="48" viewBox="0 0 24 24" fill="white"><path d="M19 9.5L12 3L5 9.5V20h14V9.5z"/></svg>';
            }}
          />
        </div>

        {/* Title */}
        <h1 className="text-[26px] font-black text-white tracking-[-0.5px] mb-1">
          Harisree Warehouse
        </h1>
        <p className="text-[13px] font-medium text-white/70 tracking-[1.2px] mb-8 uppercase">
          Stock · Purchase · Delivery
        </p>

        {/* Loading / Status */}
        {status === "loading" && (
          <div className="w-6 h-6 border-[2.5px] border-white/80 border-t-transparent rounded-full animate-spin" />
        )}

        {status === "retrying" && (
          <div className="flex flex-col items-center gap-3">
            <div className="w-6 h-6 border-[2.5px] border-white/80 border-t-transparent rounded-full animate-spin" />
            <p className="text-[13px] text-white/80 font-medium text-center">
              Server is warming up. Retrying in 10 seconds...
            </p>
          </div>
        )}

        {status === "error" && (
          <div className="flex flex-col items-center gap-4">
            <p className="text-[13px] text-white/80 font-medium text-center max-w-[280px]">
              {errorMessage}
            </p>
            <button
              onClick={handleRetry}
              className="h-[44px] px-6 bg-white/20 text-white font-semibold text-[14px] rounded-[10px] flex items-center gap-2 hover:bg-white/30 transition-colors"
            >
              Retry
            </button>
            <button
              onClick={() => navigate("/login")}
              className="text-[13px] text-white/70 font-medium hover:text-white transition-colors"
            >
              Use another account
            </button>
          </div>
        )}
      </div>

      <p className="absolute bottom-6 text-[11px] text-white/40">
        Harisree Warehouse v1.0
      </p>
    </div>
  );
}
