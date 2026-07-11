import { useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { MdKey, MdLock, MdVisibility, MdVisibilityOff, MdCheckCircle, MdArrowBack } from "react-icons/md";
import { api } from "../../../lib/api/client";
import { AuthPageShell } from "../components/AuthPageShell";
import { AuthNetworkErrorBanner } from "../components/AuthNetworkErrorBanner";

export function ResetPasswordPage() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const token = searchParams.get("token") || "";

  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [showPass, setShowPass] = useState(false);
  const [showConfirm, setShowConfirm] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [networkError, setNetworkError] = useState(false);
  const [success, setSuccess] = useState(false);

  const passError = !password
    ? "Password is required"
    : password.length < 8
    ? "Use at least 8 characters"
    : null;
  const confirmError = !confirm
    ? "Confirm your password"
    : password !== confirm
    ? "Passwords do not match"
    : null;
  const isFormValid = password.length >= 8 && password === confirm;

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (passError || confirmError) return;
    setLoading(true);
    setError(null);
    setNetworkError(false);
    try {
      await api.post("/auth/reset-password", { token, newPassword: password });
      setSuccess(true);
    } catch (err: unknown) {
      const e = err as {
        response?: { status?: number; data?: { detail?: string } };
        code?: string;
        message?: string;
      };
      if (!e.response || e.code === "ERR_NETWORK") {
        setNetworkError(true);
      } else {
        const detail = e.response?.data?.detail;
        setError(detail || "Something went wrong. Try again.");
      }
    } finally {
      setLoading(false);
    }
  }

  if (!token) {
    return (
      <div className="relative min-h-screen">
        <div className="absolute top-0 left-0 right-0 z-20 flex items-center h-14 px-4">
          <button
            onClick={() => navigate("/login")}
            className="flex items-center gap-1 text-brand-primary font-bold text-[18px]"
          >
            <MdArrowBack size={22} />
            New password
          </button>
        </div>
        <AuthPageShell>
          <h2 className="text-[20px] font-extrabold text-brand-primary text-center mb-4">
            Invalid link
          </h2>
          <p className="text-[13px] text-[#374151] leading-[1.35] text-center mb-6">
            Open the reset link from your email, or request a new one.
          </p>
          <button
            onClick={() => navigate("/forgot-password")}
            className="w-full h-[50px] bg-brand-primary text-white text-[16px] font-bold rounded-[10px] mb-3"
          >
            Request reset link
          </button>
          <button
            onClick={() => navigate("/login")}
            className="w-full text-center text-brand-accent text-[14px] font-semibold hover:underline"
          >
            Back to sign in
          </button>
        </AuthPageShell>
      </div>
    );
  }

  return (
    <div className="relative min-h-screen">
      <div className="absolute top-0 left-0 right-0 z-20 flex items-center h-14 px-4">
        <button
          onClick={() => navigate("/login")}
          className="flex items-center gap-1 text-brand-primary font-bold text-[18px]"
        >
          <MdArrowBack size={22} />
          New password
        </button>
      </div>

      <AuthPageShell>
        {networkError && <AuthNetworkErrorBanner onRetry={() => setNetworkError(false)} />}

        {success ? (
          <>
            <div className="flex items-start gap-2 mb-4">
              <MdCheckCircle size={20} className="text-profit shrink-0 mt-0.5" />
              <p className="text-[13px] font-medium text-[#065F46] leading-[1.35]">
                Password updated. You can sign in now.
              </p>
            </div>
            <button
              onClick={() => navigate("/login")}
              className="w-full h-[50px] bg-brand-primary text-white text-[16px] font-bold rounded-[10px]"
            >
              Go to sign in
            </button>
          </>
        ) : (
          <form onSubmit={handleSubmit} className="space-y-4">
            <h2 className="text-[20px] font-extrabold text-brand-primary text-center">
              Choose a new password
            </h2>
            <p className="text-[13px] text-[#374151] leading-[1.35] text-center">
              Use at least 8 characters.
            </p>

            {/* Password field */}
            <div>
              <div
                className={`flex items-center h-[50px] bg-[#F3F4F6] rounded-[10px] overflow-hidden ${
                  passError
                    ? "border border-loss border-[1.5px]"
                    : "border border-[#E5E7EB] focus-within:border-brand-primary focus-within:border-[1.5px]"
                }`}
              >
                <span className="flex items-center justify-center min-w-[44px] min-h-[44px] text-[#6B7280]">
                  <MdKey size={20} />
                </span>
                <input
                  type={showPass ? "text" : "password"}
                  placeholder="New password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  className="flex-1 bg-transparent h-full px-0 py-3.5 text-[15px] font-medium text-input-text placeholder:text-[#9CA3AF] placeholder:font-normal focus:outline-none"
                  autoComplete="new-password"
                  autoFocus
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
                <p className="text-loss text-[12px] font-medium mt-1.5 pl-1">{passError}</p>
              )}
            </div>

            {/* Confirm password */}
            <div>
              <div
                className={`flex items-center h-[50px] bg-[#F3F4F6] rounded-[10px] overflow-hidden ${
                  confirmError
                    ? "border border-loss border-[1.5px]"
                    : "border border-[#E5E7EB] focus-within:border-brand-primary focus-within:border-[1.5px]"
                }`}
              >
                <span className="flex items-center justify-center min-w-[44px] min-h-[44px] text-[#6B7280]">
                  <MdLock size={20} />
                </span>
                <input
                  type={showConfirm ? "text" : "password"}
                  placeholder="Confirm password"
                  value={confirm}
                  onChange={(e) => setConfirm(e.target.value)}
                  className="flex-1 bg-transparent h-full px-0 py-3.5 text-[15px] font-medium text-input-text placeholder:text-[#9CA3AF] placeholder:font-normal focus:outline-none"
                  autoComplete="new-password"
                />
                <button
                  type="button"
                  onClick={() => setShowConfirm(!showConfirm)}
                  className="flex items-center justify-center min-w-[44px] min-h-[44px] text-[#6B7280]"
                  tabIndex={-1}
                >
                  {showConfirm ? <MdVisibilityOff size={22} /> : <MdVisibility size={22} />}
                </button>
              </div>
              {confirmError && (
                <p className="text-loss text-[12px] font-medium mt-1.5 pl-1">{confirmError}</p>
              )}
            </div>

            {error && (
              <p className="text-loss text-[13px] font-medium">{error}</p>
            )}

            <button
              type="submit"
              disabled={loading || !isFormValid}
              className="w-full h-[50px] bg-brand-primary text-white text-[16px] font-bold rounded-[10px] disabled:bg-[#E5E7EB] disabled:text-[#6B7280] transition-colors duration-150 flex items-center justify-center"
            >
              {loading ? (
                <div className="w-[22px] h-[22px] border-2 border-white border-t-transparent rounded-full animate-spin" />
              ) : (
                "Update password"
              )}
            </button>

            <button
              type="button"
              onClick={() => navigate("/login")}
              className="w-full text-center text-brand-accent text-[14px] font-semibold hover:underline"
            >
              Back to sign in
            </button>
          </form>
        )}
      </AuthPageShell>
    </div>
  );
}
