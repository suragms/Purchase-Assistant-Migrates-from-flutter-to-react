import axios, { AxiosError } from "axios";
import type { InternalAxiosRequestConfig } from "axios";

const BASE_URL = import.meta.env.VITE_API_BASE_URL || "http://localhost:5131";

export const api = axios.create({
  baseURL: `${BASE_URL}/v1`,
  timeout: 30_000,
  headers: { "X-Requested-With": "harisree-app" },
});

let accessToken: string | null = null;
let refreshToken: string | null = null;
let refreshPromise: Promise<boolean> | null = null;

export function setTokens(access: string, refresh: string) {
  accessToken = access;
  refreshToken = refresh;
  api.defaults.headers.common["Authorization"] = `Bearer ${access}`;
}

export function clearTokens() {
  accessToken = null;
  refreshToken = null;
  delete api.defaults.headers.common["Authorization"];
}

export function getAccessToken() {
  return accessToken;
}

async function attemptRefresh(): Promise<boolean> {
  if (!refreshToken) return false;
  try {
    const res = await axios.post(`${BASE_URL}/v1/auth/refresh`, {
      refreshToken,
    });
    const access = res.data.access_token || res.data.accessToken || res.data.access;
    const refresh = res.data.refresh_token || res.data.refreshToken || res.data.refresh;
    setTokens(access, refresh ?? refreshToken);
    return true;
  } catch {
    return false;
  }
}

api.interceptors.request.use((config: InternalAxiosRequestConfig) => {
  if (accessToken && !config.headers.Authorization) {
    config.headers.Authorization = `Bearer ${accessToken}`;
  }
  return config;
});

api.interceptors.response.use(
  (res) => res,
  async (error: AxiosError) => {
    const original = error.config as InternalAxiosRequestConfig & { _retry?: boolean };
    if (error.response?.status === 401 && !original._retry) {
      original._retry = true;
      if (!refreshPromise) {
        refreshPromise = attemptRefresh().finally(() => {
          refreshPromise = null;
        });
      }
      const ok = await refreshPromise;
      if (ok && accessToken) {
        original.headers.Authorization = `Bearer ${accessToken}`;
        return api(original);
      }
      clearTokens();
      window.location.href = "/login?notice=session_expired";
    }
    return Promise.reject(error);
  }
);
