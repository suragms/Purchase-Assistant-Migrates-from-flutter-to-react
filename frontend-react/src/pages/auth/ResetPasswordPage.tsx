import { useState, useCallback } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { MdArrowBack, MdLock, MdVisibility, MdVisibilityOff } from "react-icons/md";
import { resetPassword } from "../../lib/api/auth";
import { AuthPageShell } from "../../features/auth/components/AuthPageShell";
import { AuthNetworkErrorBanner } from "../../features/auth/components/AuthNetworkErrorBanner";

function getPasswordStrength(pw: string): { label: string; color: string; width: string } {
  if (!pw) return { label: "", color: "bg-[#E5E7EB]", width: "0%" };
  if (pw.length < 6) return { label: "Weak", color: "bg-[#EF4444]", width: "33%" };
  if (pw.length < 10) return { label: "Medium", color: "bg-[#F59E0B]", width: "66%" };
  return { label: "Strong", color: "bg-[#22C55E]", width: "100%" };
}

export default function ResetPasswordPage() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const token = searchParams.get("token") || "";

  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [showConfirm, setShowConfirm] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [networkError, setNetworkError] = useState(false);
  const [success, setSuccess] = useState(false);

  const strength = getPasswordStrength(password);
  const passwordsMatch = password === confirmPassword;
  const canSubmit = password.length >= 6 && confirmPassword.length >= 6 && passwordsMatch;

  const handleSubmit = useCallback(async (e: React.FormEvent) => {
    e.preventDefault();

    if (!token) {
      setError("Invalid or missing reset token");
      return;
    }

    if (password.length < 6) {
      setError("Password must be at least 6 characters");
      return;
    }

    if (password !== confirmPassword) {
      setError("Passwords do not match");
      return;
    }

    setLoading(true);
    setError(null);
    setNetworkError(false);

    try {
      await resetPassword(token, password);
      setSuccess(true);
    } catch (err: unknown) {
      const e = err as { response?: { status?: number; data?: { message?: string } }; code?: string };
      if (e.code === "ERR_NETWORK" || !e.response) {
        setNetworkError(true);
      } else {
        setError(e.response?.data?.message || "Something went wrong. The link may be invalid or expired.");
      }
    } finally {
      setLoading(false);
    }
  }, [token, password, confirmPassword]);

  if (!token) {
    return (
      <div className="relative min-h-screen">
        <div className="absolute top-0 left-0 right-0 z-20 flex items-center h-14 px-4">
          <button
            onClick={() => navigate("/login")}
            className="flex items-center gap-1 text-brand-primary font-bold text-[18px]"
          >
            <MdArrowBack size={22} />
            Reset password
          </button>
        </div>
        <AuthPageShell>
          <p className="text-[13px] font-medium text-loss text-center py-4">
            Invalid or expired password reset link.
          </p>
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
          Reset password
        </button>
      </div>

      <AuthPageShell>
        {networkError && <AuthNetworkErrorBanner onRetry={() => setNetworkError(false)} />}

        {success ? (
          <>
            <div className="flex flex-col items-center gap-3 py-4">
              <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="#22C55E" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M22 11.08V12a10 10 0 11-5.93-9.14" />
                <polyline points="22 4 12 14.01 9 11.01" />
              </svg>
              <p className="text-[15px] font-bold text-brand-primary text-center">
                Password updated!
              </p>
              <p className="text-[13px] text-text-muted text-center leading-[1.35]">
                Your password has been reset successfully.
              </p>
            </div>
            <button
              onClick={() => navigate("/login")}
              className="w-full h-[50px] bg-brand-primary text-white text-[16px] font-bold rounded-[10px] flex items-center justify-center"
            >
              Back to sign in
            </button>
          </>
        ) : (
          <form onSubmit={handleSubmit} className="space-y-4">
            <h2 className="text-[20px] font-extrabold text-brand-primary text-center">
              Reset password
            </h2>
            <p className="text-[13px] text-[#374151] leading-[1.35] text-center">
              Enter your new password.
            </p>

            {/* Password field */}
            <div>
              <div className={`flex items-center h-[50px] bg-[#F3F4F6] rounded-[10px] border ${error === "Password must be at least 6 characters" || error?.includes("link may be invalid") ? "border-[#DC2626]" : "border-[#E5E7EB]"} focus-within:border-brand-primary focus-within:border-[1.5px] overflow-hidden`}>
                <span className="flex items-center justify-center min-w-[44px] min-h-[44px] text-[#6B7280]">
                  <MdLock size={20} />
                </span>
                <input
                  type={showPassword ? "text" : "password"}
                  placeholder="New password"
                  value={password}
                  onChange={(e) => { setPassword(e.target.value); setError(null); }}
                  className="flex-1 bg-transparent h-full px-0 py-3.5 text-[15px] font-medium text-input-text placeholder:text-[#9CA3AF] placeholder:font-normal focus:outline-none"
                  autoComplete="new-password"
                  autoFocus
                />
                <button
                  type="button"
                  onClick={() => setShowPassword(!showPassword)}
                  className="flex items-center justify-center min-w-[44px] min-h-[44px] text-[#6B7280]"
                  tabIndex={-1}
                >
                  {showPassword ? <MdVisibilityOff size={20} /> : <MdVisibility size={20} />}
                </button>
              </div>

              {/* Strength indicator */}
              {password.length > 0 && (
                <div className="mt-2">
                  <div className="h-[4px] bg-[#E5E7EB] rounded-full overflow-hidden">
                    <div
                      className={`h-full rounded-full transition-all duration-300 ${strength.color}`}
                      style={{ width: strength.width }}
                    />
                  </div>
                  <p className={`text-[11px] font-medium mt-1 ${strength.label === "Weak" ? "text-[#EF4444]" : strength.label === "Medium" ? "text-[#F59E0B]" : "text-[#22C55E]"}`}>
                    {strength.label}
                  </p>
                </div>
              )}
            </div>

            {/* Confirm password field */}
            <div>
              <div className={`flex items-center h-[50px] bg-[#F3F4F6] rounded-[10px] border ${error === "Passwords do not match" ? "border-[#DC2626]" : "border-[#E5E7EB]"} focus-within:border-brand-primary focus-within:border-[1.5px] overflow-hidden`}>
                <span className="flex items-center justify-center min-w-[44px] min-h-[44px] text-[#6B7280]">
                  <MdLock size={20} />
                </span>
                <input
                  type={showConfirm ? "text" : "password"}
                  placeholder="Confirm password"
                  value={confirmPassword}
                  onChange={(e) => { setConfirmPassword(e.target.value); setError(null); }}
                  className="flex-1 bg-transparent h-full px-0 py-3.5 text-[15px] font-medium text-input-text placeholder:text-[#9CA3AF] placeholder:font-normal focus:outline-none"
                  autoComplete="new-password"
                />
                <button
                  type="button"
                  onClick={() => setShowConfirm(!showConfirm)}
                  className="flex items-center justify-center min-w-[44px] min-h-[44px] text-[#6B7280]"
                  tabIndex={-1}
                >
                  {showConfirm ? <MdVisibilityOff size={20} /> : <MdVisibility size={20} />}
                </button>
              </div>
              {error === "Passwords do not match" && (
                <p className="text-loss text-[12px] font-medium mt-1.5 pl-1">{error}</p>
              )}
            </div>

            {error && error !== "Passwords do not match" && error !== "Password must be at least 6 characters" && (
              <p className="text-loss text-[12px] font-medium text-center">{error}</p>
            )}

            <button
              type="submit"
              disabled={loading || !canSubmit}
              className="w-full h-[50px] bg-brand-primary text-white text-[16px] font-bold rounded-[10px] disabled:bg-[#E5E7EB] disabled:text-[#6B7280] transition-colors duration-150 flex items-center justify-center"
            >
              {loading ? (
                <div className="w-[22px] h-[22px] border-2 border-white border-t-transparent rounded-full animate-spin" />
              ) : (
                "Reset password"
              )}
            </button>
          </form>
        )}
      </AuthPageShell>
    </div>
  );
}
