import type { ReactNode } from "react";
import { cn } from "@/lib/utils";
import { DsIcon } from "./ds-icon";
import { DS_FOCUS } from "./focus";

type DsStatTileProps = {
  value: ReactNode;
  label: string;
  /** Sous-texte : contexte du chiffre, en une phrase. */
  hint?: string;
  href?: string;
  linkLabel?: string;
  /** « alert » : réservé au critique (bordure et chiffre en couleur d'erreur, plus une icône). */
  tone?: "default" | "alert";
  className?: string;
};

export function DsStatTile({
  value,
  label,
  hint,
  href,
  linkLabel,
  tone = "default",
  className,
}: DsStatTileProps) {
  const alert = tone === "alert";
  return (
    <div
      className={cn(
        "flex min-w-0 flex-col gap-xs border bg-surface-container-lowest p-md",
        alert ? "border-error accent-bar" : "border-outline-variant",
        className,
      )}
    >
      <p className={cn("font-display text-3xl", alert ? "text-error" : "text-primary")}>{value}</p>
      <p className="inline-flex items-center gap-1 font-body-md text-body-md text-on-surface">
        {alert && <DsIcon name="error" filled className="text-error" />}
        {label}
      </p>
      {hint && <p className="font-body-sm text-body-sm text-on-surface-variant">{hint}</p>}
      {href && linkLabel && (
        <a
          href={href}
          className={cn(
            "inline-flex min-h-11 items-center font-body-sm text-body-sm text-primary underline underline-offset-4",
            DS_FOCUS,
          )}
        >
          {linkLabel}
        </a>
      )}
    </div>
  );
}
