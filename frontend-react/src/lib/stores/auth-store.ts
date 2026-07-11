import { create } from "zustand";
import type { Session } from "../api/types";

interface AuthState {
  session: Session | null;
  isAuthenticated: boolean;
  isStaff: boolean;
  isOwner: boolean;
  businessId: string | null;
  setSession: (session: Session) => void;
  clearSession: () => void;
}

export const useAuthStore = create<AuthState>((set) => ({
  session: null,
  isAuthenticated: false,
  isStaff: false,
  isOwner: false,
  businessId: null,
  setSession: (session) =>
    set({
      session,
      isAuthenticated: true,
      isStaff: session.primaryBusiness.role.toLowerCase() === "staff",
      isOwner: session.primaryBusiness.role.toLowerCase() !== "staff",
      businessId: session.primaryBusiness.id,
    }),
  clearSession: () =>
    set({
      session: null,
      isAuthenticated: false,
      isStaff: false,
      isOwner: false,
      businessId: null,
    }),
}));
