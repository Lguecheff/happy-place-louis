import { timeAgo } from "@/lib/dashboard";
import { cn } from "@/lib/utils";
import { DsIcon } from "./ds-icon";

type DsFreshnessProps = {
  /** Date ISO de la dernière mise à jour. */
  at: string;
  /** Donnée trop ancienne : texte en couleur d'alerte, icône d'avertissement et mention pour les lecteurs d'écran. */
  stale?: boolean;
  className?: string;
};

export function DsFreshness({ at, stale, className }: DsFreshnessProps) {
  return (
    <p
      className={cn(
        "inline-flex items-center gap-1 font-label-md text-label-md normal-case tracking-normal",
        stale ? "text-error" : "text-on-surface-variant",
        className,
      )}
    >
      <DsIcon name={stale ? "warning" : "schedule"} className="text-base" />
      {stale && <span className="sr-only">Donnée ancienne. </span>}
      <time dateTime={at}>Mis à jour {timeAgo(at)}</time>
    </p>
  );
}
