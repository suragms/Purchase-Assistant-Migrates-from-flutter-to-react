import { type ButtonHTMLAttributes, type ReactNode } from "react";
import { cva, type VariantProps } from "class-variance-authority";

const buttonVariants = cva(
  "inline-flex items-center justify-center font-plus-jakarta font-bold transition-all duration-[160ms] ease-out select-none disabled:opacity-55 disabled:cursor-not-allowed focus:outline-none",
  {
    variants: {
      variant: {
        primary:
          "text-white bg-gradient-to-r from-[#0E4F46] via-[#159A8A] to-[#0E7669] rounded-xl h-[52px] w-full shadow-[0_8px_20px_rgba(99,102,241,0.35)] hover:shadow-[0_12px_28px_rgba(99,102,241,0.50),0_0_32px_rgba(124,58,237,0.22)] hover:scale-[1.006] active:scale-[0.992]",
        secondary:
          "text-text-primary bg-white border border-input-border rounded-xl h-[48px] w-full data-[dense=true]:h-[44px]",
        ghost:
          "text-brand-accent bg-transparent rounded-xl h-[40px] px-3 py-2 hover:bg-brand-accent/10 active:bg-brand-accent/14",
        icon: "text-brand-primary/60 hover:text-brand-primary/80 hover:bg-brand-primary/8 focus:bg-brand-accent/12 rounded-xl h-12 w-12 p-3",
      },
      size: {
        sm: "text-sm px-3 py-2",
        md: "text-base px-4 py-3",
        lg: "text-lg px-6 py-4",
      },
    },
    defaultVariants: {
      variant: "primary",
      size: "md",
    },
  }
);

interface ButtonProps
  extends ButtonHTMLAttributes<HTMLButtonElement>,
    VariantProps<typeof buttonVariants> {
  loading?: boolean;
  dense?: boolean;
  children: ReactNode;
}

export function Button({
  variant,
  size,
  loading,
  dense,
  className,
  children,
  disabled,
  ...props
}: ButtonProps) {
  return (
    <button
      className={buttonVariants({ variant, size, className })}
      data-dense={dense || undefined}
      disabled={disabled || loading}
      {...props}
    >
      {loading ? (
        <svg
          className="animate-spin h-[22px] w-[22px] text-white"
          xmlns="http://www.w3.org/2000/svg"
          fill="none"
          viewBox="0 0 24 24"
        >
          <circle
            className="opacity-25"
            cx="12"
            cy="12"
            r="10"
            stroke="currentColor"
            strokeWidth="2.2"
          />
          <path
            className="opacity-75"
            fill="currentColor"
            d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"
          />
        </svg>
      ) : (
        children
      )}
    </button>
  );
}
