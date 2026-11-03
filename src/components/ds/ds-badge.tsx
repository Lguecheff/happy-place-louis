import type { ReactNode } from "react";
import { cn } from "@/lib/utils";
import { DsIcon } from "./ds-icon";

export type DsBadgeVariant = "critical" | "watch" | "status" | "neutral";

// Bordure sur toutes les variantes (transparente sauf status) : même hauteur partout.
const VARIANTS: Record<DsBadgeVariant, string> = {
  critical: "border-transparent bg-error-container text-on-error-container",
  watch: "border-transparent bg-tertiary-fixed text-on-tertiary-fixed",
  status: "border-primary bg-transparent text-primary",
  neutral: "border-transparent bg-surface-container-highest text-on-surface",
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
        "inline-flex items-center gap-1 border px-xs py-0.5 font-label-md text-label-md normal-case tracking-normal",
        VARIANTS[variant],
        className,
      )}
    >
      {/* `!` : la feuille Google des icônes (24 px, hors couche) l'emporte sinon sur text-sm. */}
      {icon && <DsIcon name={icon} className="text-sm! leading-none!" />}
      {children}
    </span>
  );
}
