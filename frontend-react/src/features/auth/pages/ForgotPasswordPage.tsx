import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { MdEmail, MdCheckCircle, MdArrowBack } from "react-icons/md";
import { api } from "../../../lib/api/client";
import { AuthPageShell } from "../components/AuthPageShell";
import { AuthNetworkErrorBanner } from "../components/AuthNetworkErrorBanner";

export function ForgotPasswordPage() {
  const navigate = useNavigate();
  const [email, setEmail] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [networkError, setNetworkError] = useState(false);
  const [success, setSuccess] = useState(false);
  const [devToken, setDevToken] = useState<string | null>(null);

  const emailRegex = /^[\w.+-]+@[\w.-]+\.\w{2,}$/;
  const isValid = emailRegex.test(email);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!email.trim()) {
      setError("Email is required");
      return;
    }
    if (!isValid) {
      setError("Enter a valid email");
      return;
    }
    setLoading(true);
    setError(null);
    setNetworkError(false);
    try {
      const res = await api.post("/auth/forgot-password", { email: email.trim() });
      setSuccess(true);
      if (res.data?.dev_reset_token) {
        setDevToken(res.data.dev_reset_token);
      }
    } catch (err: unknown) {
      const e = err as { response?: { status?: number }; code?: string; message?: string };
      if (!e.response || e.code === "ERR_NETWORK") {
        setNetworkError(true);
      } else {
        setError("Something went wrong. Please try again.");
      }
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="relative min-h-screen">
      {/* Transparent AppBar equivalent */}
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
            <div className="flex items-start gap-2 mb-4">
              <MdCheckCircle size={20} className="text-profit shrink-0 mt-0.5" />
              <p className="text-[13px] font-medium text-[#065F46] leading-[1.35]">
                If this email is registered, reset instructions will be sent. Check your inbox.
              </p>
            </div>

            {devToken && (
              <div className="bg-[#F3F4F6] rounded-[10px] p-3 mb-4">
                <p className="text-[12px] text-text-muted mb-2">
                  Development: use the button below to set a new password (email is not sent yet).
                </p>
                <button
                  onClick={() => navigate(`/reset-password?token=${devToken}`)}
                  className="w-full h-[44px] bg-brand-primary/12 text-brand-primary font-bold text-[14px] rounded-[10px]"
                >
                  Set new password (dev)
                </button>
              </div>
            )}

            <button
              onClick={() => navigate("/login")}
              className="w-full text-center text-brand-accent text-[14px] font-semibold hover:underline"
            >
              Back to sign in
            </button>
          </>
        ) : (
          <form onSubmit={handleSubmit} className="space-y-4">
            <h2 className="text-[20px] font-extrabold text-brand-primary text-center">
              Forgot password?
            </h2>
            <p className="text-[13px] text-[#374151] leading-[1.35] text-center">
              Enter your email. If an account exists, you will receive reset instructions.
            </p>

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
              {error && (
                <p className="text-loss text-[12px] font-medium mt-1.5 pl-1">{error}</p>
              )}
            </div>

            <button
              type="submit"
              disabled={loading || !email.trim()}
              className="w-full h-[50px] bg-brand-primary text-white text-[16px] font-bold rounded-[10px] disabled:bg-[#E5E7EB] disabled:text-[#6B7280] transition-colors duration-150 flex items-center justify-center"
            >
              {loading ? (
                <div className="w-[22px] h-[22px] border-2 border-white border-t-transparent rounded-full animate-spin" />
              ) : (
                "Send reset link"
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
