import { type ImgHTMLAttributes, useState } from "react";

const avatarColors = [
  "bg-[#159A8A]",
  "bg-[#D4AF37]",
  "bg-[#3B82F6]",
  "bg-[#8B5CF6]",
  "bg-[#F472B6]",
  "bg-[#FB923C]",
  "bg-[#10B981]",
  "bg-[#E53935]",
];

function hashName(name: string): number {
  let hash = 0;
  for (let i = 0; i < name.length; i++) {
    hash = name.charCodeAt(i) + ((hash << 5) - hash);
  }
  return Math.abs(hash);
}

function initials(name: string): string {
  const parts = name.trim().split(/\s+/);
  if (parts.length === 0) return "?";
  if (parts.length === 1) return parts[0].charAt(0).toUpperCase();
  return (parts[0].charAt(0) + parts[parts.length - 1].charAt(0)).toUpperCase();
}

interface AvatarProps extends Omit<ImgHTMLAttributes<HTMLImageElement>, "src"> {
  name: string;
  src?: string | null;
  size?: number;
}

export function Avatar({
  name,
  src,
  size = 40,
  className,
  style,
  ...props
}: AvatarProps) {
  const [imgError, setImgError] = useState(false);

  if (src && !imgError) {
    return (
      <img
        src={src}
        alt={name}
        onError={() => setImgError(true)}
        className={`rounded-full object-cover ${className || ""}`}
        style={{ width: size, height: size, ...style }}
        {...props}
      />
    );
  }

  const colorIndex = hashName(name) % avatarColors.length;
  const letter = initials(name);

  return (
    <div
      className={`rounded-full flex items-center justify-center text-white font-bold select-none ${avatarColors[colorIndex]} ${className || ""}`}
      style={{
        width: size,
        height: size,
        fontSize: size * 0.38,
        ...style,
      }}
      aria-label={name}
    >
      {letter}
    </div>
  );
}
