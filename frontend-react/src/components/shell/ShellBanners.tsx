import { useState, useEffect } from "react";
import { MdWifiOff, MdSync } from "react-icons/md";

export function ShellBanners() {
  const [online, setOnline] = useState(navigator.onLine);
  const [pendingSync] = useState(0);

  useEffect(() => {
    const goOnline = () => setOnline(true);
    const goOffline = () => setOnline(false);
    window.addEventListener("online", goOnline);
    window.addEventListener("offline", goOffline);
    return () => {
      window.removeEventListener("online", goOnline);
      window.removeEventListener("offline", goOffline);
    };
  }, []);

  return (
    <>
      {!online && (
        <div className="flex items-center gap-2 px-4 py-2 bg-amber text-white text-sm font-semibold">
          <MdWifiOff size={18} />
          <span>You are offline. Some features may be unavailable.</span>
        </div>
      )}
      {pendingSync > 0 && (
        <div className="flex items-center gap-2 px-4 py-2 bg-[#2563EB] text-white text-sm font-semibold">
          <MdSync size={18} />
          <span>{pendingSync} entries pending sync</span>
        </div>
      )}
    </>
  );
}
