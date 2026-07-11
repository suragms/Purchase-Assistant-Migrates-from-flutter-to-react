import type { HTMLAttributes } from "react";

interface SkeletonProps extends HTMLAttributes<HTMLDivElement> {
  width?: string | number;
  height?: string | number;
  borderRadius?: string | number;
}

export function Skeleton({
  width = "100%",
  height = 20,
  borderRadius = 12,
  className,
  style,
  ...props
}: SkeletonProps) {
  return (
    <div
      className={`shimmer ${className || ""}`}
      style={{
        width,
        height,
        borderRadius,
        ...style,
      }}
      {...props}
    />
  );
}

interface ListSkeletonProps {
  rows?: number;
  rowHeight?: number;
  gap?: number;
}

export function ListSkeleton({
  rows = 6,
  rowHeight = 84,
  gap = 10,
}: ListSkeletonProps) {
  return (
    <div className="flex flex-col" style={{ gap, padding: "12px 16px 100px" }}>
      {Array.from({ length: rows }).map((_, i) => (
        <Skeleton key={i} height={rowHeight} borderRadius={12} />
      ))}
    </div>
  );
}

interface DetailSkeletonProps {
  gap?: number;
}

export function DetailSkeleton({ gap = 12 }: DetailSkeletonProps) {
  return (
    <div className="flex flex-col" style={{ gap, padding: "12px 16px 120px" }}>
      <Skeleton height={128} borderRadius={14} />
      <Skeleton height={160} borderRadius={14} />
      <Skeleton height={96} borderRadius={14} />
    </div>
  );
}
