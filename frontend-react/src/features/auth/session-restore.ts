import { api, setTokens, getAccessToken } from "../../lib/api/client";
import { useAuthStore } from "../../lib/stores/auth-store";
import type { Session, BusinessUser } from "../../lib/api/types";

const STORAGE_ACCESS_KEY = "hexa_access_token";
const STORAGE_REFRESH_KEY = "hexa_refresh_token";
const CACHE_BUSINESSES_KEY = "session_businesses_cache";

export function readStoredTokens(): {
  access: string | null;
  refresh: string | null;
} {
  try {
    return {
      access: localStorage.getItem(STORAGE_ACCESS_KEY),
      refresh: localStorage.getItem(STORAGE_REFRESH_KEY),
    };
  } catch {
    return { access: null, refresh: null };
  }
}

export function writeStoredTokens(access: string, refresh: string) {
  try {
    localStorage.setItem(STORAGE_ACCESS_KEY, access);
    localStorage.setItem(STORAGE_REFRESH_KEY, refresh);
  } catch {
    // silently fail
  }
}

export function clearStoredTokens() {
  try {
    localStorage.removeItem(STORAGE_ACCESS_KEY);
    localStorage.removeItem(STORAGE_REFRESH_KEY);
    localStorage.removeItem(CACHE_BUSINESSES_KEY);
  } catch {
    // silently fail
  }
}

function loadCachedBusinesses(): BusinessUser[] | null {
  try {
    const raw = localStorage.getItem(CACHE_BUSINESSES_KEY);
    return raw ? JSON.parse(raw) : null;
  } catch {
    return null;
  }
}

function isJwtExpiredOrNearExpiry(token: string, skewSec = 90): boolean {
  try {
    const payload = JSON.parse(atob(token.split(".")[1]));
    const now = Math.floor(Date.now() / 1000);
    return payload.exp < now + skewSec;
  } catch {
    return true;
  }
}

export interface RestoreResult {
  session: Session | null;
  error?: "expired" | "network" | "none";
  errorMessage?: string;
}

export async function tryRestoreSession(): Promise<RestoreResult> {
  const tokens = readStoredTokens();
  if (!tokens.access || !tokens.refresh) {
    return { session: null, error: "none" };
  }

  setTokens(tokens.access, tokens.refresh);

  // Refresh if near expiry
  if (isJwtExpiredOrNearExpiry(tokens.access)) {
    try {
      const res = await api.post("/auth/refresh", {
        refreshToken: tokens.refresh,
      });
      const access = res.data.access_token || res.data.accessToken || res.data.access;
      const refresh = res.data.refresh_token || res.data.refreshToken || res.data.refresh;
      setTokens(access, refresh ?? tokens.refresh);
      writeStoredTokens(access, refresh ?? tokens.refresh);
    } catch {
      clearStoredTokens();
      return { session: null, error: "expired", errorMessage: "Session expired. Please sign in again." };
    }
  }

  // Fetch businesses
  try {
    const accessToken = getAccessToken();
    const res = await api.get("/me", {
      headers: accessToken ? { Authorization: `Bearer ${accessToken}` } : undefined,
    });
    const userData = res.data as {
      id: string;
      email: string;
      name: string;
      primaryBusiness: { id: string; name: string; role: string; currency: string };
    };
    const session: Session = {
      id: userData.id,
      email: userData.email,
      name: userData.name,
      primaryBusiness: userData.primaryBusiness,
    };
    const { setSession } = useAuthStore.getState();
    setSession(session);
    return { session };
  } catch (err: unknown) {
    const isNetworkError =
      err && typeof err === "object" && "code" in err &&
      (err as { code: string }).code === "ERR_NETWORK";

    if (isNetworkError) {
      // Fallback to cached businesses
      const cached = loadCachedBusinesses();
      if (cached && cached.length > 0) {
        const first = cached[0];
        const session: Session = {
          id: first.id,
          email: tokens.access || "",
          name: first.name,
          primaryBusiness: {
            id: first.id,
            name: first.name,
            role: first.role,
            currency: "INR",
          },
        };
        const { setSession } = useAuthStore.getState();
        setSession(session);
        return { session };
      }
      return { session: null, error: "network", errorMessage: "API not reachable. Check your connection." };
    }

    clearStoredTokens();
    return { session: null, error: "expired", errorMessage: "Session expired. Please sign in again." };
  }
}
