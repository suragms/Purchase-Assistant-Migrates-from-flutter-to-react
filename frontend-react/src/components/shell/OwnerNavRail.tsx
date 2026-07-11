import { useNavigate, useLocation } from "react-router-dom";
import {
  MdGridView,
  MdInventory2,
  MdBarChart,
  MdReceiptLong,
  MdSearch,
  MdHome,
} from "react-icons/md";
import { NavigationRail } from "../ui/NavigationRail";

const railItems = [
  {
    icon: <MdHome size={24} />,
    selectedIcon: <MdGridView size={24} />,
    label: "Home",
    value: "/home",
  },
  {
    icon: <MdInventory2 size={24} />,
    selectedIcon: <MdInventory2 size={24} />,
    label: "Stock",
    value: "/stock",
  },
  {
    icon: <MdBarChart size={24} />,
    selectedIcon: <MdBarChart size={24} />,
    label: "Reports",
    value: "/reports",
  },
  {
    icon: <MdReceiptLong size={24} />,
    selectedIcon: <MdReceiptLong size={24} />,
    label: "History",
    value: "/purchase",
  },
  {
    icon: <MdSearch size={24} />,
    selectedIcon: <MdSearch size={24} />,
    label: "Search",
    value: "/search",
  },
];

interface OwnerNavRailProps {
  extended: boolean;
}

export function OwnerNavRail({ extended }: OwnerNavRailProps) {
  const navigate = useNavigate();
  const location = useLocation();

  const currentValue = railItems.find((item) =>
    location.pathname.startsWith(item.value)
  )?.value;

  return (
    <NavigationRail
      items={railItems}
      value={currentValue || "/home"}
      onChange={(v) => navigate(v)}
      extended={extended}
    />
  );
}
