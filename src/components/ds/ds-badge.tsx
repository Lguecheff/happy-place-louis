import type { ReactNode } from "react";
import { cn } from "@/lib/utils";
import { DsIcon } from "./ds-icon";

export type DsBadgeVariant = "critical" | "watch" | "status" | "neutral";

const VARIANTS: Record<DsBadgeVariant, string> = {
  critical: "bg-error-container text-on-error-container",
  watch: "bg-tertiary-fixed text-on-tertiary-fixed",
  status: "border border-primary bg-transparent text-primary",
  neutral: "bg-surface-container-highest text-on-surface",
};

type DsBadgeProps = {
  variant?: DsBadgeVariant;
  /** Toujours un texte : la couleur seule ne porte jamais le sens. */
  children: ReactNode;
  /** Symbole décoratif optionnel, jamais seul. */
  icon?: string;
  className?: string;
};

export function DsBadge({ variant = "neutral", children, icon, className }: DsBadgeProps) {
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1 px-xs py-0.5 font-label-md text-label-md normal-case tracking-normal",
        VARIANTS[variant],
        className,
      )}
    >
      {icon && <DsIcon name={icon} className="text-base" />}
      {children}
    </span>
  );
}
