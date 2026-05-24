import { type FormEvent, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { AdminErrorBanner } from '../../components/AdminErrorBanner'
import { adminPost, apiBase, devErrorDetail, setAdminToken, userSafeLoginError } from '../../lib/api'
import './login.css'

const features = [
  'Business & subscription oversight',
  'API keys & integrations',
  'Usage and health monitoring',
  'Feature flags & rollout',
]

export default function LoginPage() {
  const nav = useNavigate()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [remember, setRemember] = useState(true)
  const [err, setErr] = useState<string | null>(null)
  const [errDev, setErrDev] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)

  async function onSubmit(e: FormEvent) {
    e.preventDefault()
    setErr(null)
    setErrDev(null)
    setBusy(true)
    try {
      const res = await adminPost<{ access_token: string }>('/v1/admin/login', { email, password })
      setAdminToken(res.access_token)
      nav('/', { replace: true })
    } catch (e: unknown) {
      setErr(userSafeLoginError(e))
      setErrDev(devErrorDetail(e))
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="login-page login-shell">
      <aside className="login-brand" aria-label="Product">
        <div className="login-brand-glow login-brand-glow--a" />
        <div className="login-brand-glow login-brand-glow--b" />
        <div className="login-brand-inner">
          <div className="login-brand-mark">H</div>
          <h1 className="login-brand-title">Harisree Warehouse</h1>
          <p className="login-brand-tagline">Purchase Intelligence Platform</p>
          <p className="login-brand-sub">Operator console — secure admin access.</p>
          <ul className="login-brand-list">
            {features.map((t) => (
              <li key={t}>
                <span className="login-brand-dot" aria-hidden />
                {t}
              </li>
            ))}
          </ul>
        </div>
      </aside>

      <main className="login-form-col">
        <div className="login-card login-card--elevated login-page__card">
          <h2 className="login-form-heading">Sign in</h2>
          <p className="login-hint">Use your administrator email and password.</p>
          <form onSubmit={onSubmit}>
            <label className="login-float-label">
              <span>Email</span>
              <input
                type="email"
                autoComplete="username"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
                placeholder="you@company.com"
              />
            </label>
            <label className="login-float-label">
              <span>Password</span>
              <input
                type="password"
                autoComplete="current-password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
                placeholder="••••••••"
              />
            </label>
            <div className="login-row">
              <label className="login-remember">
                <input
                  type="checkbox"
                  checked={remember}
                  onChange={(e) => setRemember(e.target.checked)}
                />
                Remember me
              </label>
              <button type="button" className="login-link-btn" onClick={() => alert('Contact a super admin to reset your password.')}>
                Forgot password?
              </button>
            </div>
            {err && <AdminErrorBanner message={err} devDetail={errDev} />}
            <button type="submit" className="login-cta" disabled={busy}>
              {busy ? 'Signing in…' : 'Sign in'}
            </button>
          </form>
          <div className="login-social-placeholder">
            <span>Other providers</span>
            <div className="login-social-row">
              <button type="button" className="login-pill" disabled>
                Apple · soon
              </button>
              <button type="button" className="login-pill" disabled>
                Microsoft · soon
              </button>
            </div>
          </div>
          {import.meta.env.DEV && (
            <p className="login-dev-api">
              Dev: service URL <code>{apiBase()}</code>
            </p>
          )}
        </div>
      </main>
    </div>
  )
}
