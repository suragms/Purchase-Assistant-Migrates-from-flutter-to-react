import { Outlet, useNavigate, useLocation } from "react-router-dom";
import {
  LuLayoutGrid, LuPackage, LuChartBar, LuReceipt, LuSearch, LuPlus,
  LuSettings, LuLogOut,
} from "react-icons/lu";
import { BottomNav, Fab } from "../../components/ui";
import { useState, useEffect } from "react";
import { logout } from "../../lib/api/auth";
import { useAuthStore } from "../../lib/stores/auth-store";

const SHELL_BRANCHES = [
  { label: "Home", icon: LuLayoutGrid, activeIcon: LuLayoutGrid, path: "/home" },
  { label: "Stock", icon: LuPackage, activeIcon: LuPackage, path: "/stock" },
  { label: "Reports", icon: LuChartBar, activeIcon: LuChartBar, path: "/reports" },
  { label: "History", icon: LuReceipt, activeIcon: LuReceipt, path: "/purchase" },
  { label: "Search", icon: LuSearch, activeIcon: LuSearch, path: "/search" },
];

const kShellRailMin = 600;
const kShellRailExtendedMin = 900;

function branchIndexForPath(path: string): number {
  for (let i = 0; i < SHELL_BRANCHES.length; i++) {
    if (path.startsWith(SHELL_BRANCHES[i].path)) return i;
  }
  return -1;
}

export function OwnerAppShell() {
  const navigate = useNavigate();
  const location = useLocation();
  const { clearSession } = useAuthStore();
  const [width, setWidth] = useState(window.innerWidth);

  useEffect(() => {
    const onResize = () => setWidth(window.innerWidth);
    window.addEventListener("resize", onResize);
    return () => window.removeEventListener("resize", onResize);
  }, []);

  const showRail = width >= kShellRailMin;
  const railExtended = width >= kShellRailExtendedMin;

  const currentBranch = branchIndexForPath(location.pathname);
  const currentPath = currentBranch >= 0 ? SHELL_BRANCHES[currentBranch].path : "/home";

  function handleTabChange(value: string) {
    navigate(value);
  }

  const bottomNavItems = SHELL_BRANCHES.map((b) => ({
    icon: <b.icon size={22} />,
    label: b.label,
    value: b.path,
  }));

  function handleFabAction() {
    navigate("/purchase/new");
  }

  function handleLogout() {
    logout();
    clearSession();
    navigate("/login", { replace: true });
  }

  return (
    <div className="min-h-screen bg-brand-background flex flex-col">
      {showRail ? (
        <div className="flex flex-1">
          {/* Navigation Rail */}
          <nav
            className={`flex flex-col bg-white border-r border-brand-border shrink-0 ${
              railExtended ? "w-60" : "w-14"
            }`}
          >
            <div className="flex flex-col gap-1 py-3 px-1 flex-1">
              {SHELL_BRANCHES.map((b, i) => {
                const selected = currentBranch === i;
                return (
                  <button
                    key={b.path}
                    onClick={() => handleTabChange(b.path)}
                    className={`flex items-center gap-3 rounded-xl transition-colors ${
                      railExtended ? "px-3 py-2.5" : "justify-center py-3"
                    } ${
                      selected
                        ? "bg-brand-primary/12 text-brand-primary"
                        : "text-text-muted hover:bg-black/5"
                    }`}
                    title={railExtended ? undefined : b.label}
                  >
                    <b.icon size={22} />
                    {railExtended && (
                      <span className={`text-[13px] ${selected ? "font-bold" : "font-medium"}`}>
                        {b.label}
                      </span>
                    )}
                  </button>
                );
              })}
            </div>
            <div className="border-t border-brand-border px-1 py-2">
              <button
                onClick={() => navigate("/settings")}
                className={`flex items-center gap-3 rounded-xl text-text-muted hover:bg-black/5 ${
                  railExtended ? "w-full px-3 py-2.5" : "w-full justify-center py-3"
                }`}
                title={railExtended ? undefined : "Settings"}
              >
                <LuSettings size={22} />
                {railExtended && <span className="text-[13px] font-medium">Settings</span>}
              </button>
              <button
                onClick={handleLogout}
                className={`flex items-center gap-3 rounded-xl text-loss hover:bg-loss/10 ${
                  railExtended ? "w-full px-3 py-2.5" : "w-full justify-center py-3"
                }`}
                title={railExtended ? undefined : "Logout"}
              >
                <LuLogOut size={22} />
                {railExtended && <span className="text-[13px] font-medium">Logout</span>}
              </button>
            </div>
            {railExtended && (
              <div className="px-4 py-3 border-t border-brand-border">
                <p className="text-[11px] font-bold text-text-muted uppercase tracking-wider">Owner</p>
              </div>
            )}
          </nav>

          {/* Content */}
          <main className="flex-1 overflow-y-auto pb-4">
            <Outlet />
          </main>
        </div>
      ) : (
        <>
          <main className="flex-1 overflow-y-auto pb-[88px]">
            <Outlet />
          </main>
          <div className="fixed bottom-0 left-0 right-0 px-3 pb-3 z-50">
            <BottomNav
              items={bottomNavItems}
              value={currentPath}
              onChange={handleTabChange}
              fab={
                <Fab
                  icon={<LuPlus size={22} />}
                  onClick={handleFabAction}
                />
              }
            />
            <div className="mt-2 grid grid-cols-2 gap-2">
              <button className="h-10 rounded-xl bg-white text-sm font-bold text-brand-primary shadow" onClick={() => navigate("/settings")}>Settings</button>
              <button className="h-10 rounded-xl bg-white text-sm font-bold text-loss shadow" onClick={handleLogout}>Logout</button>
            </div>
          </div>
        </>
      )}
    </div>
  );
}
