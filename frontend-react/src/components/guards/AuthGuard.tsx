import { Navigate, Outlet, useLocation } from "react-router-dom";
import { useAuthStore } from "../../lib/stores/auth-store";

const PUBLIC_ROUTES = [
  "/splash",
  "/login",
  "/forgot-password",
  "/reset-password",
];

export function AuthGuard() {
  const { isAuthenticated, isStaff } = useAuthStore();
  const location = useLocation();
  const path = location.pathname;

  // Allow public routes without auth
  if (PUBLIC_ROUTES.some((r) => path === r)) {
    return <Outlet />;
  }

  if (!isAuthenticated) {
    return <Navigate to={`/login?redirect=${encodeURIComponent(path)}`} replace />;
  }

  // Staff user on owner route → staff equivalent
  if (isStaff && !path.startsWith("/staff")) {
    const staffMap: Record<string, string> = {
      "/home": "/staff/home",
      "/stock": "/staff/stock",
      "/search": "/staff/search",
      "/purchase": "/staff/deliveries",
    };
    const target = staffMap[path];
    if (target) return <Navigate to={target} replace />;
    return <Navigate to="/staff/home" replace />;
  }

  // Owner user on staff route → owner home
  if (!isStaff && path.startsWith("/staff")) {
    return <Navigate to="/home" replace />;
  }

  // Authenticated on public route → home
  if (PUBLIC_ROUTES.some((r) => path === r)) {
    return <Navigate to={isStaff ? "/staff/home" : "/home"} replace />;
  }

  return <Outlet />;
}
