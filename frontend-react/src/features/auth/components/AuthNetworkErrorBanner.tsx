import { MdWifiOff } from "react-icons/md";

interface AuthNetworkErrorBannerProps {
  onRetry?: () => void;
  detail?: string;
}

export function AuthNetworkErrorBanner({ onRetry, detail }: AuthNetworkErrorBannerProps) {
  return (
    <div className="bg-[#FFF7ED] border border-[#FDBA74] rounded-[10px] px-2.5 py-2.5 mb-3">
      <div className="flex items-start gap-2.5">
        <MdWifiOff size={20} className="text-[#9A3412] mt-0.5 shrink-0" />
        <div className="flex-1 min-w-0">
          <p className="text-[13px] font-semibold text-[#9A3412] leading-tight">
            Can't reach server
          </p>
          {detail && (
            <p className="text-[12px] text-[#9A3412] leading-tight mt-0.5">
              {detail}
            </p>
          )}
        </div>
        {onRetry && (
          <button
            onClick={onRetry}
            className="shrink-0 text-[13px] font-semibold text-brand-accent hover:underline px-2 py-1"
          >
            Retry
          </button>
        )}
      </div>
    </div>
  );
}
