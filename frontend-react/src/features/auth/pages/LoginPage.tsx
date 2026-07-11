import { useState, useEffect, useRef } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { MdEmail, MdLock, MdVisibility, MdVisibilityOff, MdFingerprint } from "react-icons/md";
import { login as apiLogin } from "../../../lib/api/auth";
import { useAuthStore } from "../../../lib/stores/auth-store";
import { tryRestoreSession, readStoredTokens, clearStoredTokens } from "../session-restore";
import { BiometricLogin } from "../biometric-login";
import { AUTH_ASSETS } from "../auth-brand-assets";
import { AuthNetworkErrorBanner } from "../components/AuthNetworkErrorBanner";

function useWidth() {
  const [width, setWidth] = useState(window.innerWidth);
  useEffect(() => {
    const onResize = () => setWidth(window.innerWidth);
    window.addEventListener("resize", onResize);
    return () => window.removeEventListener("resize", onResize);
  }, []);
  return width;
}

export function LoginPage() {
  const width = useWidth();
  const isMobile = width < 768;

  if (isMobile) return <LoginPageMobile />;
  return <LoginPageDesktop />;
}

function LoginPageDesktop() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const { setSession, isStaff } = useAuthStore();

  const [email, setEmail] = useState("anandu@gmail.com");
  const [password, setPassword] = useState("123456789");
  const [showPass, setShowPass] = useState(false);
  const [loading, setLoading] = useState(false);
  const [showValidation, setShowValidation] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [networkError, setNetworkError] = useState(false);
  const [bioReady, setBioReady] = useState(false);
  const [bioEmail, setBioEmail] = useState<string | null>(null);
  const [resuming, setResuming] = useState(true);

  const emailValid = email.includes("@") && email.length >= 5;
  const passValid = password.length >= 6;
  const isFormValid = emailValid && passValid;
  const emailError = showValidation && !emailValid ? "Enter a valid email address" : null;
  const passError = showValidation && !passValid ? "Password must be at least 6 characters" : null;

  const notice = searchParams.get("notice");

  useEffect(() => {
    if (notice === "session_expired") {
      clearStoredTokens();
      window.history.replaceState(null, "", "/login");
    }
    const load = async () => {
      const bioEmail = BiometricLogin.savedEmail();
      if (bioEmail) {
        setBioEmail(bioEmail);
        if (BiometricLogin.isAvailable()) {
          const tokens = readStoredTokens();
          if (tokens.access) setBioReady(true);
        }
      }
      const result = await tryRestoreSession();
      if (result.session) {
        navigate(isStaff ? "/staff/home" : "/home", { replace: true });
        return;
      }
      setResuming(false);
    };
    load();
  }, [notice]);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setShowValidation(true);
    if (!isFormValid) return;
    setLoading(true);
    setError(null);
    setNetworkError(false);
    try {
      const data = await apiLogin({ email, password });
      setSession(data.session);
      BiometricLogin.saveEmail(email);
      const isUserStaff = data.session.primaryBusiness.role.toLowerCase() === "staff";
      navigate(isUserStaff ? "/staff/home" : "/home", { replace: true });
    } catch (err: unknown) {
      handleLoginError(err);
    } finally {
      setLoading(false);
    }
  }

  function handleLoginError(err: unknown) {
    const e = err as {
      response?: { status?: number; data?: { detail?: string } };
      code?: string;
      message?: string;
    };

    if (!e.response) {
      // Network error
      if (e.code === "ERR_NETWORK" || e.message?.includes("Network")) {
        setNetworkError(true);
        return;
      }
    }

    const status = e.response?.status;
    const detail = e.response?.data?.detail?.toLowerCase() || "";

    if (status === 401) {
      setError("Invalid email or password. Try again.");
    } else if (status === 403) {
      if (detail.includes("blocked")) {
        setError("This account is blocked. Contact your owner.");
      } else if (detail.includes("inactive")) {
        setError("This account is inactive.");
      } else {
        setError("Sign-in not allowed for this account.");
      }
    } else if (status === 422) {
      setError("Use your full login email (e.g. 1234567890@staff.harisree.local) and password from the owner.");
    } else {
      setError("Something went wrong. Please try again.");
    }
  }

  async function handleBioSignIn() {
    if (!bioEmail) return;
    setEmail(bioEmail);
    setLoading(true);
    setError(null);
    try {
      const result = await tryRestoreSession();
      if (result.session) {
        navigate(isStaff ? "/staff/home" : "/home", { replace: true });
      } else if (result.error === "expired") {
        setError("Session expired — sign in with password once.");
      } else {
        setError("Biometric sign-in failed. Use password.");
      }
    } catch {
      setError("Biometric sign-in failed. Use password.");
    } finally {
      setLoading(false);
    }
  }

  if (resuming) {
    return (
      <div className="min-h-screen flex items-center justify-center" style={{ backgroundColor: "#0E4F46" }}>
        <div className="w-12 h-12 border-4 border-white border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  return (
    <div className="relative min-h-screen overflow-hidden">
      {/* Background */}
      <div className="absolute inset-0">
        <img
          src={AUTH_ASSETS.background}
          alt=""
          className="w-full h-full object-cover"
          onError={(e) => {
            e.currentTarget.style.display = "none";
          }}
        />
        <div className="absolute inset-0 backdrop-blur-[12px]" />
        <div
          className="absolute inset-0"
          style={{
            background: `linear-gradient(to bottom, rgba(255,255,255,0.35) 0%, rgba(247,249,246,0.75) 100%)`,
          }}
        />
      </div>

      <div className="relative z-10 min-h-screen flex items-start justify-center pt-8 pb-6 overflow-y-auto">
        <div className="w-full px-4" style={{ maxWidth: 420 }}>
          {/* Logo */}
          <div className="flex flex-col items-center gap-3 mb-6">
            <div className="w-[68px] h-[68px] rounded-full bg-white flex items-center justify-center shadow-[0_4px_16px_rgba(0,0,0,0.12)]">
              <LogoFallback size={68} />
            </div>
            <h2 className="text-[24px] font-extrabold text-brand-primary text-center leading-tight">
              Harisree Agency
            </h2>
            <p className="text-[14px] font-medium text-text-muted text-center">
              Warehouse Management
            </p>
          </div>

          {/* Form card */}
          <div className="rounded-[16px] overflow-hidden backdrop-blur-[20px] bg-white/86 border border-white/65 shadow-[0_8px_20px_rgba(0,0,0,0.06)] p-4">
            {notice === "session_expired" && (
              <NoticeBanner message="Session expired. Please sign in again." />
            )}

            <h1 className="text-[20px] font-extrabold text-brand-primary text-center mb-4">
              Sign In
            </h1>

            {networkError && (
              <AuthNetworkErrorBanner
                onRetry={() => {
                  setNetworkError(false);
                  handleSubmit(new Event("submit") as unknown as React.FormEvent);
                }}
              />
            )}

            <form onSubmit={handleSubmit} className="space-y-3">
              <div>
                <div className="flex items-center h-[50px] bg-[#F3F4F6] rounded-[10px] border border-[#E5E7EB] focus-within:border-brand-primary focus-within:border-[1.5px] overflow-hidden">
                  <span className="flex items-center justify-center min-w-[44px] min-h-[44px] text-[#6B7280]">
                    <MdEmail size={20} />
                  </span>
                  <input
                    type="email"
                    placeholder="Email"
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    className="flex-1 bg-transparent h-full px-0 py-3.5 text-[15px] font-medium text-input-text placeholder:text-[#9CA3AF] placeholder:font-normal focus:outline-none"
                    autoComplete="email"
                    autoFocus
                  />
                </div>
                {emailError && (
                  <p className="text-loss text-[12px] font-medium mt-1 pl-1">{emailError}</p>
                )}
              </div>

              <div>
                <div
                  className={`flex items-center h-[50px] bg-[#F3F4F6] rounded-[10px] overflow-hidden ${
                    passError
                      ? "border border-loss border-[1.5px]"
                      : "border border-[#E5E7EB] focus-within:border-brand-primary focus-within:border-[1.5px]"
                  }`}
                >
                  <span className="flex items-center justify-center min-w-[44px] min-h-[44px] text-[#6B7280]">
                    <MdLock size={20} />
                  </span>
                  <input
                    type={showPass ? "text" : "password"}
                    placeholder="Password"
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    className="flex-1 bg-transparent h-full px-0 py-3.5 text-[15px] font-medium text-input-text placeholder:text-[#9CA3AF] placeholder:font-normal focus:outline-none"
                    autoComplete="current-password"
                  />
                  <button
                    type="button"
                    onClick={() => setShowPass(!showPass)}
                    className="flex items-center justify-center min-w-[44px] min-h-[44px] text-[#6B7280]"
                    tabIndex={-1}
                  >
                    {showPass ? <MdVisibilityOff size={22} /> : <MdVisibility size={22} />}
                  </button>
                </div>
                {passError && (
                  <p className="text-loss text-[12px] font-medium mt-1 pl-1">{passError}</p>
                )}
              </div>

              {error && (
                <p className="text-loss text-[13px] font-medium">{error}</p>
              )}

              <button
                type="submit"
                disabled={loading}
                className="w-full h-[50px] bg-brand-primary text-white text-[16px] font-bold rounded-[10px] disabled:bg-[#E5E7EB] disabled:text-[#6B7280] transition-colors duration-150 flex items-center justify-center shadow-[0_2px_4px_rgba(14,79,70,0.30)]"
              >
                {loading ? (
                  <div className="w-[22px] h-[22px] border-2 border-white border-t-transparent rounded-full animate-spin" />
                ) : (
                  "Sign In"
                )}
              </button>
            </form>

            {bioReady && bioEmail && (
              <button
                onClick={handleBioSignIn}
                className="w-full h-[50px] mt-3 flex items-center justify-center gap-2 rounded-[10px] bg-brand-primary/12 text-brand-primary font-bold text-[15px]"
              >
                <MdFingerprint size={28} />
                <span>Sign in with fingerprint / Face ID</span>
              </button>
            )}
            {bioReady && bioEmail && (
              <p className="text-center text-[12px] text-[#6B7280] mt-1">{bioEmail}</p>
            )}

            <button
              onClick={() => navigate("/forgot-password")}
              className="w-full text-center text-text-muted text-[14px] font-medium mt-4 hover:text-brand-accent transition-colors"
            >
              Forgot password?
            </button>

            <p className="text-center text-[12px] text-[#6B7280] mt-2">
              Contact your manager to reset password
            </p>

            <p className="text-center text-[11px] text-[#9CA3AF] mt-4">© 2026</p>
          </div>
        </div>
      </div>
    </div>
  );
}

function LoginPageMobile() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const { setSession, isStaff } = useAuthStore();

  const [email, setEmail] = useState("anandu@gmail.com");
  const [password, setPassword] = useState("123456789");
  const [showPass, setShowPass] = useState(false);
  const [loading, setLoading] = useState(false);
  const [showValidation, setShowValidation] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [networkError, setNetworkError] = useState(false);
  const [bioReady, setBioReady] = useState(false);
  const [bioEmail, setBioEmail] = useState<string | null>(null);
  const [resuming, setResuming] = useState(true);
  const [visible, setVisible] = useState(false);

  const emailValid = email.includes("@") && email.length >= 5;
  const passValid = password.length >= 6;
  const isFormValid = emailValid && passValid;
  const emailError = showValidation && !emailValid ? "Enter a valid email address" : null;
  const passError = showValidation && !passValid ? "Password must be at least 6 characters" : null;

  const notice = searchParams.get("notice");

  useEffect(() => {
    if (notice === "session_expired") {
      clearStoredTokens();
      window.history.replaceState(null, "", "/login");
    }
    const timer = setTimeout(() => setVisible(true), 50);
    const load = async () => {
      const bioEmail = BiometricLogin.savedEmail();
      if (bioEmail) {
        setBioEmail(bioEmail);
        if (BiometricLogin.isAvailable()) {
          const tokens = readStoredTokens();
          if (tokens.access) setBioReady(true);
        }
      }
      const result = await tryRestoreSession();
      if (result.session) {
        navigate(isStaff ? "/staff/home" : "/home", { replace: true });
        return;
      }
      setResuming(false);
    };
    load();
    return () => clearTimeout(timer);
  }, [notice]);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setShowValidation(true);
    if (!isFormValid) return;
    setLoading(true);
    setError(null);
    setNetworkError(false);
    try {
      const data = await apiLogin({ email, password });
      setSession(data.session);
      BiometricLogin.saveEmail(email);
      const isUserStaff = data.session.primaryBusiness.role.toLowerCase() === "staff";
      navigate(isUserStaff ? "/staff/home" : "/home", { replace: true });
    } catch (err: unknown) {
      handleLoginError(err);
    } finally {
      setLoading(false);
    }
  }

  function handleLoginError(err: unknown) {
    const e = err as { response?: { status?: number; data?: { detail?: string } }; code?: string; message?: string };
    if (!e.response) {
      if (e.code === "ERR_NETWORK" || e.message?.includes("Network")) {
        setNetworkError(true);
        return;
      }
    }
    const status = e.response?.status;
    const detail = e.response?.data?.detail?.toLowerCase() || "";
    if (status === 401) setError("Invalid email or password. Try again.");
    else if (status === 403) {
      if (detail.includes("blocked")) setError("This account is blocked. Contact your owner.");
      else if (detail.includes("inactive")) setError("This account is inactive.");
      else setError("Sign-in not allowed for this account.");
    } else if (status === 422) setError("Use your full login email (e.g. 1234567890@staff.harisree.local) and password from the owner.");
    else setError("Something went wrong. Please try again.");
  }

  async function handleBioSignIn() {
    if (!bioEmail) return;
    setEmail(bioEmail);
    setLoading(true);
    setError(null);
    try {
      const result = await tryRestoreSession();
      if (result.session) navigate(isStaff ? "/staff/home" : "/home", { replace: true });
      else if (result.error === "expired") setError("Session expired — sign in with password once.");
      else setError("Biometric sign-in failed. Use password.");
    } catch {
      setError("Biometric sign-in failed. Use password.");
    } finally {
      setLoading(false);
    }
  }

  if (resuming) {
    return (
      <div className="min-h-screen flex items-center justify-center" style={{ backgroundColor: "#0E4F46" }}>
        <div className="w-12 h-12 border-4 border-white border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  return (
    <div className="relative min-h-screen overflow-hidden" onClick={() => (document.activeElement as HTMLElement)?.blur()}>
      {/* Hero background with blur + gradient scrim */}
      <div className="absolute inset-0">
        <img
          src={AUTH_ASSETS.background}
          alt=""
          className="w-full h-full object-cover"
          onError={(e) => { e.currentTarget.style.display = "none"; }}
        />
        <div className="absolute inset-0 backdrop-blur-[8px]" />
        <div
          className="absolute inset-0"
          style={{
            background: `linear-gradient(to bottom, rgba(6,46,40,0.55) 0%, rgba(14,79,70,0.65) 50%, rgba(247,249,246,0.80) 100%)`,
          }}
        />
      </div>

      {/* Content */}
      <div className="relative z-10 min-h-screen flex flex-col justify-center px-4 pt-12 pb-8">
        {/* Top logo */}
        <div
          className={`transition-all duration-500 ease-out ${visible ? "opacity-100 translate-y-0" : "opacity-0 translate-y-[6%]"}`}
        >
          <div className="flex flex-col items-center mb-6">
            <div className="w-[72px] h-[72px] rounded-full bg-white flex items-center justify-center shadow-[0_6px_20px_rgba(0,0,0,0.12)]">
              <LogoFallback size={72} />
            </div>
            <h2 className="text-[26px] font-extrabold text-white text-center mt-3 leading-tight">
              Harisree Agency
            </h2>
            <p className="text-[15px] font-medium text-white/80 text-center">
              Warehouse Management
            </p>
          </div>
        </div>

        {/* Glass card */}
        <div
          className={`transition-all duration-500 ease-out delay-75 ${visible ? "opacity-100 translate-y-0" : "opacity-0 translate-y-[6%]"}`}
        >
          <div className="rounded-[28px] overflow-hidden backdrop-blur-[30px] bg-white/86 border border-white/65 shadow-[0_10px_30px_rgba(0,0,0,0.15)] p-6">
            {notice === "session_expired" && (
              <NoticeBanner message="Session expired. Please sign in again." />
            )}
            {notice === "owner_only" && (
              <NoticeBanner message="Accounts are created by your owner. Sign in with the credentials they shared." />
            )}

            {networkError && (
              <AuthNetworkErrorBanner
                onRetry={() => {
                  setNetworkError(false);
                  handleSubmit(new Event("submit") as unknown as React.FormEvent);
                }}
              />
            )}

            <form onSubmit={handleSubmit} className="space-y-4">
              {/* Email field */}
              <div>
                <div
                  className={`flex items-center h-[56px] bg-[#F3F4F6] rounded-[16px] overflow-hidden ${
                    emailError
                      ? "border border-loss border-[1.5px]"
                      : "border border-[#E5E7EB] focus-within:border-brand-primary focus-within:border-[1.5px]"
                  }`}
                >
                  <span className="flex items-center justify-center min-w-[48px] min-h-[48px] text-[#6B7280]">
                    <MdEmail size={20} />
                  </span>
                  <input
                    type="email"
                    placeholder="Email"
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    className="flex-1 bg-transparent h-full px-0 py-4 text-[15px] font-medium text-input-text placeholder:text-[#9CA3AF] placeholder:font-normal focus:outline-none"
                    autoComplete="email"
                    autoFocus
                  />
                </div>
                {emailError && (
                  <p className="text-loss text-[12px] font-medium mt-1 pl-1">{emailError}</p>
                )}
              </div>

              {/* Password field */}
              <div>
                <div
                  className={`flex items-center h-[56px] bg-[#F3F4F6] rounded-[16px] overflow-hidden ${
                    passError
                      ? "border border-loss border-[1.5px]"
                      : "border border-[#E5E7EB] focus-within:border-brand-primary focus-within:border-[1.5px]"
                  }`}
                >
                  <span className="flex items-center justify-center min-w-[48px] min-h-[48px] text-[#6B7280]">
                    <MdLock size={20} />
                  </span>
                  <input
                    type={showPass ? "text" : "password"}
                    placeholder="Password"
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    className="flex-1 bg-transparent h-full px-0 py-4 text-[15px] font-medium text-input-text placeholder:text-[#9CA3AF] placeholder:font-normal focus:outline-none"
                    autoComplete="current-password"
                  />
                  <button
                    type="button"
                    onClick={() => setShowPass(!showPass)}
                    className="flex items-center justify-center min-w-[48px] min-h-[48px] text-[#6B7280]"
                    tabIndex={-1}
                  >
                    <AnimatedIcon show={showPass} />
                  </button>
                </div>
                {passError && (
                  <p className="text-loss text-[12px] font-medium mt-1 pl-1">{passError}</p>
                )}
              </div>

              {error && (
                <p className="text-loss text-[13px] font-medium">{error}</p>
              )}

              <button
                type="submit"
                disabled={loading}
                className="w-full h-[56px] bg-brand-primary text-white text-[16px] font-bold rounded-[16px] disabled:bg-[#E5E7EB] disabled:text-[#6B7280] transition-colors duration-150 flex items-center justify-center shadow-[0_2px_4px_rgba(14,79,70,0.30)]"
              >
                {loading ? (
                  <div className="w-[22px] h-[22px] border-2 border-white border-t-transparent rounded-full animate-spin" />
                ) : (
                  "Sign In"
                )}
              </button>
            </form>

            {bioReady && bioEmail && (
              <button
                onClick={handleBioSignIn}
                className="w-full h-[56px] mt-3 flex items-center justify-center gap-2 rounded-[16px] bg-brand-primary/12 text-brand-primary font-bold text-[15px]"
              >
                <MdFingerprint size={28} />
                <span>Sign in with fingerprint / Face ID</span>
              </button>
            )}
            {bioReady && bioEmail && (
              <p className="text-center text-[12px] text-[#6B7280] mt-1">{bioEmail}</p>
            )}

            {/* Bottom links */}
            <button
              onClick={() => navigate("/forgot-password")}
              className="w-full text-center text-text-muted text-[14px] font-medium mt-4 hover:text-brand-accent transition-colors"
            >
              Forgot password?
            </button>

            <p className="text-center text-[12px] text-text-muted mt-2">
              Contact your manager to reset password
            </p>
            <p className="text-center text-[12px] text-[#9CA3AF] mt-3">© 2026</p>
          </div>
        </div>
      </div>
    </div>
  );
}

function AnimatedIcon({ show }: { show: boolean }) {
  return (
    <span className="inline-flex transition-transform duration-200">
      {show ? <MdVisibilityOff size={22} /> : <MdVisibility size={22} />}
    </span>
  );
}

function NoticeBanner({ message }: { message: string }) {
  return (
    <div className="bg-[#FFF7ED] border border-[#FDBA74] rounded-[10px] px-2.5 py-2.5 mb-3">
      <p className="text-[13px] font-semibold text-[#9A3412] leading-tight">{message}</p>
    </div>
  );
}

function LogoFallback({ size }: { size: number }) {
  const imgRef = useRef<HTMLImageElement>(null);
  const [showFallback, setShowFallback] = useState(false);

  return (
    <div
      className="rounded-full overflow-hidden flex items-center justify-center"
      style={{ width: size, height: size }}
    >
      <img
        ref={imgRef}
        src={AUTH_ASSETS.logo}
        alt="Harisree"
        className="w-full h-full object-cover"
        onError={() => setShowFallback(true)}
        style={{ display: showFallback ? "none" : "block" }}
      />
      {showFallback && (
        <span className="text-[28px] font-extrabold text-brand-primary">H</span>
      )}
    </div>
  );
}
