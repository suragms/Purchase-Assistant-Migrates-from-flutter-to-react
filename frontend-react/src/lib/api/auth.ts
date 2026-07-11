import { api, setTokens, clearTokens } from "./client";
import type { LoginRequest, LoginResponse, Session, BusinessUser } from "./types";
import { writeStoredTokens, clearStoredTokens } from "../../features/auth/session-restore";

export async function login(req: LoginRequest): Promise<LoginResponse> {
  const res = await api.post<any>("/auth/login", req);
  
  const accessToken = res.data.access_token || res.data.accessToken;
  const refreshToken = res.data.refresh_token || res.data.refreshToken;
  
  setTokens(accessToken, refreshToken);
  writeStoredTokens(accessToken, refreshToken);
  
  // Fetch session details from GET /v1/me
  const meRes = await api.get<Session>("/me");
  
  return {
    accessToken,
    refreshToken,
    session: meRes.data,
  };
}

export async function refreshAccessToken(
  refreshToken: string
): Promise<{ accessToken: string; refreshToken?: string }> {
  const res = await api.post("/auth/refresh", { refreshToken });
  return res.data;
}

export async function fetchBusinesses(): Promise<BusinessUser[]> {
  const res = await api.get("/me/businesses");
  return res.data;
}

export async function fetchSession(): Promise<Session> {
  const res = await api.get("/me");
  return res.data;
}

export function logout() {
  clearTokens();
  clearStoredTokens();
}

export async function forgotPassword(email: string): Promise<void> {
  await api.post("/auth/forgot-password", { email });
}

export async function resetPassword(
  token: string,
  password: string
): Promise<void> {
  await api.post("/auth/reset-password", { token, password });
}
