import { type InputHTMLAttributes, useState, type ReactNode } from "react";

interface InputProps extends InputHTMLAttributes<HTMLInputElement> {
  label?: string;
  error?: string;
  hint?: string;
  leftIcon?: ReactNode;
  rightIcon?: ReactNode;
}

export function Input({
  label,
  error,
  hint,
  leftIcon,
  rightIcon,
  className,
  id,
  ...props
}: InputProps) {
  const [focused, setFocused] = useState(false);
  const inputId = id || label?.toLowerCase().replace(/\s+/g, "-");

  return (
    <div className="flex flex-col gap-1.5">
      {label && (
        <label
          htmlFor={inputId}
          className={`text-sm font-semibold transition-colors duration-150 ${
            focused ? "text-brand-accent" : "text-text-muted"
          }`}
        >
          {label}
        </label>
      )}
      <div
        className={`relative flex items-center bg-white border rounded-xl transition-all duration-150 ${
          error
            ? "border-loss/92 shadow-none"
            : focused
            ? "border-brand-accent border-2 shadow-[0_0_0_3px_rgba(21,154,138,0.2)]"
            : "border-input-border shadow-[0_3px_10px_rgba(0,0,0,0.05)] hover:border-input-border"
        }`}
      >
        {leftIcon && (
          <span className="pl-3.5 text-text-muted">{leftIcon}</span>
        )}
        <input
          id={inputId}
          className={`w-full bg-transparent px-3.5 py-[13px] text-input-text text-[15px] font-medium placeholder:text-input-hint placeholder:font-normal focus:outline-none ${className || ""}`}
          onFocus={(e) => {
            setFocused(true);
            props.onFocus?.(e);
          }}
          onBlur={(e) => {
            setFocused(false);
            props.onBlur?.(e);
          }}
          {...props}
        />
        {rightIcon && (
          <span className="pr-3.5 text-text-muted">{rightIcon}</span>
        )}
      </div>
      {error && <p className="text-loss text-[13px] font-medium mt-0.5">{error}</p>}
      {hint && !error && (
        <p className="text-text-muted text-[13px] font-normal mt-0.5">{hint}</p>
      )}
    </div>
  );
}
