import { useNavigate, useLocation } from "react-router-dom";
import {
  MdGridView,
  MdInventory2,
  MdBarChart,
  MdReceiptLong,
  MdSearch,
  MdAdd,
} from "react-icons/md";
import { BottomNav, Fab } from "../ui/BottomNav";

const items = [
  { icon: <MdGridView size={20} />, label: "Home", value: "/home" },
  { icon: <MdInventory2 size={20} />, label: "Stock", value: "/stock" },
  { icon: <MdBarChart size={20} />, label: "Reports", value: "/reports" },
  { icon: <MdReceiptLong size={20} />, label: "History", value: "/purchase" },
  { icon: <MdSearch size={20} />, label: "Search", value: "/search" },
];

export function OwnerBottomNav() {
  const navigate = useNavigate();
  const location = useLocation();

  const hideOnPaths = ["/reports", "/purchase"];
  const shouldHide = hideOnPaths.some((p) => location.pathname === p || location.pathname.startsWith(p + "/"));

  if (shouldHide) return null;

  return (
    <div className="fixed bottom-0 left-0 right-0 z-50 px-3 pb-3">
      <BottomNav
        items={items}
        value={location.pathname}
        onChange={(v) => navigate(v)}
        fab={
          <Fab
            icon={<MdAdd size={24} />}
            onClick={() => navigate("/purchase/new")}
          />
        }
      />
    </div>
  );
}
