import { cn } from "@/lib/utils";
import { DsBadge } from "./ds-badge";
import { DsTooltip } from "./ds-tooltip";
import { DS_FOCUS } from "./focus";

/** Texte du badge « À vérifier » : infobulle, et lu par les lecteurs d'écran. */
function staleText(days: number) {
  return `Sans mise à jour depuis ${days} jour${days > 1 ? "s" : ""}. L'information est peut-être dépassée.`;
}

type DsStaleBadgeProps = {
  /** Jours sans mise à jour (`daysSince`). */
  days: number;
  /** false dans un élément déjà cliquable (ligne de recherche) : pas d'infobulle, texte lu en entier. */
  tooltip?: boolean;
  className?: string;
};

/** Badge « À vérifier » : KPI ou point bloquant sans mise à jour depuis trop longtemps. */
export function DsStaleBadge({ days, tooltip = true, className }: DsStaleBadgeProps) {
  const text = staleText(days);
  if (!tooltip) {
    return (
      <DsBadge variant="watch" icon="history" className={className}>
        À vérifier<span className="sr-only">. {text}</span>
      </DsBadge>
    );
  }
  return (
    <DsTooltip content={<p className="font-body-sm text-body-sm">{text}</p>}>
      <span tabIndex={0} className={cn("inline-flex cursor-help", DS_FOCUS, className)}>
        <DsBadge variant="watch" icon="history">
          À vérifier
        </DsBadge>
      </span>
    </DsTooltip>
  );
}
