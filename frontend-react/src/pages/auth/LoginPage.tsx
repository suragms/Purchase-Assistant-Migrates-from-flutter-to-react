import { useState, useEffect, useCallback, useRef } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { login } from "../../lib/api/auth";
import { useAuthStore } from "../../lib/stores/auth-store";
import { AuthNetworkErrorBanner } from "../../features/auth/components/AuthNetworkErrorBanner";

const AUTH_BG = "/assets/brand/getstarted_bg.webp";
const AUTH_LOGO = "/assets/brand/logo.webp";
const EMAIL_REGEX = /^[\w.+-]+@[\w.-]+\.\w{2,}$/;

function useIsMobile() {
  const [mobile, setMobile] = useState(window.innerWidth < 768);
  useEffect(() => {
    const onResize = () => setMobile(window.innerWidth < 768);
    window.addEventListener("resize", onResize);
    return () => window.removeEventListener("resize", onResize);
  }, []);
  return mobile;
}

export default function LoginPage() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const isMobile = useIsMobile();

  const notice = searchParams.get("notice");
  const msg = searchParams.get("msg");

  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const [validationError, setValidationError] = useState<string | null>(null);
  const [networkError, setNetworkError] = useState<string | null>(null);
  const { setSession, isStaff } = useAuthStore();
  const [mounted, setMounted] = useState(false);
  useEffect(() => { setMounted(true); }, []);

  const emailRef = useRef<HTMLInputElement>(null);
  const passwordRef = useRef<HTMLInputElement>(null);

  const showSessionExpired = notice === "session_expired";
  const showOwnerOnly = notice === "owner_only";
  const showExistsMsg = msg === "exists";

  const emailValid = EMAIL_REGEX.test(email);
  const canSubmit = email.trim().length > 0 && password.length >= 6;

  const handleSubmit = useCallback(async (e: React.FormEvent) => {
    e.preventDefault();
    if (!email.trim()) {
      setValidationError("Email is required");
      emailRef.current?.focus();
      return;
    }
    if (!emailValid) {
      setValidationError("Enter a valid email");
      emailRef.current?.focus();
      return;
    }
    if (!password) {
      setValidationError("Password is required");
      passwordRef.current?.focus();
      return;
    }
    if (password.length < 6) {
      setValidationError("Password must be at least 6 characters");
      passwordRef.current?.focus();
      return;
    }

    setLoading(true);
    setValidationError(null);
    setNetworkError(null);

    try {
      const data = await login({ email: email.trim(), password });
      setSession(data.session);
      const redirect = searchParams.get("redirect") || (isStaff ? "/staff/home" : "/home");
      navigate(redirect, { replace: true });
    } catch (err: unknown) {
      const e = err as { response?: { status?: number; data?: { message?: string } }; code?: string; message?: string };
      if (e.code === "ERR_NETWORK" || !e.response) {
        setNetworkError("The server could not be reached. Check your connection or try again.");
      } else {
        setValidationError(e.response?.data?.message || "Invalid email or password");
      }
    } finally {
      setLoading(false);
    }
  }, [email, password, emailValid, navigate, searchParams, setSession, isStaff]);

  const handleBiometric = useCallback(async () => {
    // Biometric login is not available on web; this is a no-op
  }, []);

  const [biometricAvailable, setBiometricAvailable] = useState(false);
  useEffect(() => {
    // WebAuthn check — only if secure context and platform supports it
    if (window.isSecureContext && typeof PublicKeyCredential !== "undefined") {
      PublicKeyCredential.isUserVerifyingPlatformAuthenticatorAvailable().then(
        (avail) => setBiometricAvailable(avail)
      ).catch(() => setBiometricAvailable(false));
    }
  }, []);

  // Mobile hero section
  const heroSection = (
    <div className="relative w-full h-[320px] shrink-0">
      <div
        className="absolute inset-0 bg-cover bg-center"
        style={{ backgroundImage: `url(${AUTH_BG})` }}
      />
      <div className="absolute inset-0 backdrop-blur-[12px]" />
      <div
        className="absolute inset-0"
        style={{
          background: "linear-gradient(to bottom, rgba(255,255,255,0.35) 0%, rgba(247,249,246,0.75) 100%)",
        }}
      />

      <div
        className="absolute inset-0 flex flex-col items-center justify-center"
        style={{
          opacity: mounted ? 1 : 0,
          transform: mounted ? "translateY(0)" : "translateY(10px)",
          transition: "opacity 400ms ease-out, transform 400ms ease-out",
        }}
      >
        <div className="w-[68px] h-[68px] rounded-full bg-white flex items-center justify-center shadow-[0_4px_16px_rgba(0,0,0,0.12)]">
          <div className="w-[68px] h-[68px] rounded-full overflow-hidden flex items-center justify-center">
            <img
              src={AUTH_LOGO}
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
        <h2 className="text-[24px] font-extrabold text-brand-primary text-center leading-tight mt-3">
          Harisree Agency
        </h2>
        <p className="text-[14px] font-medium text-text-muted text-center">
          Warehouse Management
        </p>
      </div>
    </div>
  );

  // Shared form card
  const formCard = (
    <div
      className={`
        ${isMobile
          ? "rounded-t-[20px] bg-white shadow-[0_-4px_16px_rgba(0,0,0,0.06)] px-4 pt-4 pb-6 flex-1"
          : "bg-white rounded-[20px] px-8 py-8 shadow-[0_10px_28px_rgba(14,79,70,0.08),0_4px_16px_rgba(0,0,0,0.06)] w-full max-w-[400px]"
        }
      `}
    >
      {!isMobile && (
        <div className="flex flex-col items-center gap-0 mb-5">
          <div className="w-[56px] h-[56px] rounded-full bg-white flex items-center justify-center shadow-[0_2px_8px_rgba(0,0,0,0.08)] overflow-hidden">
            <img
              src={AUTH_LOGO}
              alt="Harisree"
              className="w-full h-full object-cover"
              onError={(e) => {
                const t = e.currentTarget;
                t.style.display = "none";
                const p = t.parentElement!;
                const s = document.createElement("span");
                s.style.cssText = "font-size:24px;font-weight:800;color:#0E4F46;display:flex;align-items:center;justify-content:center;height:100%";
                s.textContent = "H";
                p.appendChild(s);
              }}
            />
          </div>
          <h2 className="text-[22px] font-extrabold text-brand-primary text-center pt-3 pb-1">
            Harisree Agency
          </h2>
          <p className="text-[14px] font-medium text-text-muted text-center">
            Warehouse Management
          </p>
        </div>
      )}

      {isMobile && (
        <p className="text-[11px] font-medium text-text-muted text-center mb-4">
          Sign in to continue
        </p>
      )}

      {showSessionExpired && !isMobile && (
        <div className="bg-[#FEF3C7] border border-[#F59E0B] rounded-[10px] px-3 py-2.5 mb-3">
          <p className="text-[12px] font-semibold text-[#92400E] leading-tight">
            Your session has expired. Please sign in again.
          </p>
        </div>
      )}

      {showOwnerOnly && !isMobile && (
        <div className="bg-[#FEF3C7] border border-[#F59E0B] rounded-[10px] px-3 py-2.5 mb-3">
          <p className="text-[12px] font-semibold text-[#92400E] leading-tight">
            Only owners can access that section.
          </p>
        </div>
      )}

      {showExistsMsg && !isMobile && (
        <div className="bg-[#ECFDF5] border border-[#6EE7B7] rounded-[10px] px-3 py-2.5 mb-3">
          <p className="text-[12px] font-semibold text-[#065F46] leading-tight">
            Account exists. Sign in to continue.
          </p>
        </div>
      )}

      {networkError && <AuthNetworkErrorBanner detail={networkError} onRetry={() => setNetworkError(null)} />}

      {showSessionExpired && isMobile && (
        <div className="bg-[#FEF3C7] border border-[#F59E0B] rounded-[10px] px-3 py-2.5 mb-3">
          <p className="text-[12px] font-semibold text-[#92400E] leading-tight">
            Your session has expired. Please sign in again.
          </p>
        </div>
      )}

      {showOwnerOnly && isMobile && (
        <div className="bg-[#FEF3C7] border border-[#F59E0B] rounded-[10px] px-3 py-2.5 mb-3">
          <p className="text-[12px] font-semibold text-[#92400E] leading-tight">
            Only owners can access that section.
          </p>
        </div>
      )}

      {showExistsMsg && isMobile && (
        <div className="bg-[#ECFDF5] border border-[#6EE7B7] rounded-[10px] px-3 py-2.5 mb-3">
          <p className="text-[12px] font-semibold text-[#065F46] leading-tight">
            Account exists. Sign in to continue.
          </p>
        </div>
      )}

      <form onSubmit={handleSubmit} noValidate>
        <div className="space-y-3">
          {/* Email field */}
          <div>
            <div className={`flex items-center h-[50px] bg-[#F3F4F6] rounded-[10px] border ${validationError === "Email is required" || validationError === "Enter a valid email" ? "border-[#DC2626]" : "border-[#E5E7EB]"} focus-within:border-brand-primary focus-within:border-[1.5px] overflow-hidden`}>
              <span className="flex items-center justify-center min-w-[44px] min-h-[44px] text-[#6B7280]">
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                  <rect x="2" y="4" width="20" height="16" rx="2" />
                  <path d="M22 6l-10 7L2 6" />
                </svg>
              </span>
              <input
                ref={emailRef}
                type="email"
                placeholder="Email"
                value={email}
                onChange={(e) => { setEmail(e.target.value); setValidationError(null); }}
                className="flex-1 bg-transparent h-full px-0 py-3.5 text-[15px] font-medium text-input-text placeholder:text-[#9CA3AF] placeholder:font-normal focus:outline-none"
                autoComplete="email"
                autoFocus
                inputMode="email"
              />
            </div>
            {(validationError === "Email is required" || validationError === "Enter a valid email") && (
              <p className="text-loss text-[12px] font-medium mt-1.5 pl-1">{validationError}</p>
            )}
          </div>

          {/* Password field */}
          <div>
            <div className={`flex items-center h-[50px] bg-[#F3F4F6] rounded-[10px] border ${validationError === "Password is required" || validationError === "Password must be at least 6 characters" || validationError === "Invalid email or password" ? "border-[#DC2626]" : "border-[#E5E7EB]"} focus-within:border-brand-primary focus-within:border-[1.5px] overflow-hidden`}>
              <span className="flex items-center justify-center min-w-[44px] min-h-[44px] text-[#6B7280]">
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                  <rect x="3" y="11" width="18" height="11" rx="2" ry="2" />
                  <path d="M7 11V7a5 5 0 0110 0v4" />
                </svg>
              </span>
              <input
                ref={passwordRef}
                type={showPassword ? "text" : "password"}
                placeholder="Password"
                value={password}
                onChange={(e) => { setPassword(e.target.value); setValidationError(null); }}
                className="flex-1 bg-transparent h-full px-0 py-3.5 text-[15px] font-medium text-input-text placeholder:text-[#9CA3AF] placeholder:font-normal focus:outline-none"
                autoComplete="current-password"
              />
              <button
                type="button"
                onClick={() => setShowPassword(!showPassword)}
                className="flex items-center justify-center min-w-[44px] min-h-[44px] text-[#6B7280]"
                tabIndex={-1}
              >
                {showPassword ? (
                  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M17.94 17.94A10.07 10.07 0 0112 20c-7 0-11-8-11-8a18.45 18.45 0 015.06-5.94M9.9 4.24A9.12 9.12 0 0112 4c7 0 11 8 11 8a18.5 18.5 0 01-2.16 3.19m-6.72-1.07a3 3 0 11-4.24-4.24" />
                    <line x1="1" y1="1" x2="23" y2="23" />
                  </svg>
                ) : (
                  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                    <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z" />
                    <circle cx="12" cy="12" r="3" />
                  </svg>
                )}
              </button>
            </div>
            {(validationError === "Password is required" || validationError === "Password must be at least 6 characters") && (
              <p className="text-loss text-[12px] font-medium mt-1.5 pl-1">{validationError}</p>
            )}
          </div>
        </div>

        {validationError === "Invalid email or password" && (
          <p className="text-loss text-[13px] font-medium mt-3 text-center">{validationError}</p>
        )}

        <button
          type="submit"
          disabled={loading || !canSubmit}
          className="w-full h-[50px] bg-brand-primary text-white text-[16px] font-bold rounded-[10px] mt-4 disabled:bg-[#E5E7EB] disabled:text-[#6B7280] transition-colors duration-150 flex items-center justify-center"
        >
          {loading ? (
            <div className="w-[22px] h-[22px] border-2 border-white border-t-transparent rounded-full animate-spin" />
          ) : (
            "Sign In"
          )}
        </button>
      </form>

      {biometricAvailable && (
        <button
          onClick={handleBiometric}
          className="w-full h-[44px] mt-3 flex items-center justify-center gap-2 bg-[#F3F4F6] text-[#374151] font-semibold text-[14px] rounded-[10px] border border-[#E5E7EB] hover:bg-[#E5E7EB] transition-colors"
        >
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M12 2a6 6 0 00-6 6v3h12V8a6 6 0 00-6-6z" />
            <path d="M6 11v4a6 6 0 0012 0v-4" />
            <path d="M12 15v3" />
          </svg>
          Sign in with biometrics
        </button>
      )}

      <button
        onClick={() => navigate("/forgot-password")}
        className="w-full text-center text-brand-accent text-[14px] font-semibold mt-4 hover:underline"
      >
        Forgot password?
      </button>

      <p className="text-[11px] text-text-muted text-center mt-5 leading-[1.4]">
        By signing in, you agree to our{" "}
        <span className="text-brand-accent font-medium">Terms</span> and{" "}
        <span className="text-brand-accent font-medium">Privacy Policy</span>
      </p>
    </div>
  );

  if (isMobile) {
    return (
      <div className="min-h-screen flex flex-col bg-[#F3F4F6]">
        {heroSection}
        <div
          className="flex-1 flex flex-col"
          style={{
            opacity: mounted ? 1 : 0,
            transform: mounted ? "translateY(0)" : "translateY(10px)",
            transition: "opacity 400ms ease-out, transform 400ms ease-out",
          }}
        >
          {formCard}
        </div>
      </div>
    );
  }

  // Desktop
  return (
    <div className="min-h-screen bg-[#F7F9F6] flex items-center justify-center px-4">
      {formCard}
    </div>
  );
}
