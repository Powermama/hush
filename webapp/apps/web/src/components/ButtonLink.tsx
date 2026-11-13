import type { AnchorHTMLAttributes, ReactNode } from "react";

const base =
  "inline-flex min-h-12 items-center justify-center rounded-full px-6 text-sm font-semibold transition duration-200 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-ink";

const variants = {
  custom: "",
  primary:
    "bg-ink text-white shadow-lg shadow-black/10 hover:-translate-y-0.5 hover:bg-black",
  secondary:
    "border border-black/10 bg-white/60 hover:-translate-y-0.5 hover:bg-white",
  light: "bg-white text-ink hover:bg-stone",
  outline: "border border-black/10 hover:bg-stone",
} as const;

type Props = AnchorHTMLAttributes<HTMLAnchorElement> & {
  children: ReactNode;
  variant?: keyof typeof variants;
};

export function buttonClassName(variant: Props["variant"] = "primary", className = "") {
  return `${base} ${variants[variant]} ${className}`;
}

export function ButtonLink({
  children,
  className = "",
  variant = "primary",
  ...props
}: Props) {
  return (
    <a className={buttonClassName(variant, className)} {...props}>
      {children}
    </a>
  );
}
