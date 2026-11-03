import type { ReactNode } from "react";
import { cn } from "@/lib/utils";
import { DsFreshness } from "./ds-freshness";
import { DsIcon } from "./ds-icon";
import { DsKpiDefinition, type DsKpiDefinitionTexts } from "./ds-kpi-definition";
import { DsTooltip } from "./ds-tooltip";
import { DS_FOCUS } from "./focus";

const ARROWS = { up: "arrow_upward", down: "arrow_downward", flat: "arrow_forward" } as const;

type DsKpiTileProps = {
  label: string;
  value: ReactNode;
  /** « headline » (titre 44 px) ou « display » (chiffre 30 px) selon la place disponible. */
  valueFont?: "headline" | "display";
  /** Tendance en texte (ex. « +2,1 pts sur 30 jours ») : la flèche seule ne suffit jamais. */
  trend?: string;
  trendDirection?: keyof typeof ARROWS;
  /** Date ISO de mise à jour, affichée par DsFreshness. */
  updatedAt?: string;
  /** Auteur de la dernière mise à jour, affiché après la date. */
  updatedBy?: string | null;
  stale?: boolean;
  /** Lien « Comprendre cet indicateur ». */
  helpHref?: string;
  /** Même libellé en bouton, pour ouvrir une fenêtre. */
  onHelp?: () => void;
  helpLabel?: string;
  /** Textes de l'indicateur : avec eux, le libellé ouvre une infobulle au survol et au focus. */
  definition?: DsKpiDefinitionTexts;
  /** Contenu ajouté en bas de tuile (ex. champ de modification). */
  children?: ReactNode;
  className?: string;
};

const HELP = cn(
  "inline-flex min-h-11 items-center self-start text-left font-body-sm text-body-sm text-primary underline underline-offset-4",
  DS_FOCUS,
);

export function DsKpiTile({
  label,
  value,
  valueFont = "display",
  trend,
  trendDirection = "flat",
  updatedAt,
  updatedBy,
  stale,
  helpHref,
  onHelp,
  helpLabel = "Comprendre cet indicateur",
  definition,
  children,
  className,
}: DsKpiTileProps) {
  return (
    <div
      className={cn(
        "flex min-w-0 flex-col gap-xs border border-outline-variant bg-surface-container-lowest p-sm",
        className,
      )}
    >
      <p className="font-label-md text-label-md normal-case tracking-normal text-on-surface-variant">
        {definition ? (
          <DsTooltip content={<DsKpiDefinition {...definition} />}>
            <span
              tabIndex={0}
              className={cn("cursor-help underline decoration-dotted underline-offset-4", DS_FOCUS)}
            >
              {label}
            </span>
          </DsTooltip>
        ) : (
          label
        )}
      </p>
      <p
        className={cn(
          "text-primary",
          valueFont === "headline" ? "font-headline-lg text-headline-lg" : "font-display text-3xl",
        )}
      >
        {value}
      </p>
      {trend && (
        <p className="inline-flex items-center gap-1 font-body-sm text-body-sm text-on-surface">
          <DsIcon name={ARROWS[trendDirection]} className="text-base" />
          {trend}
        </p>
      )}
      {updatedAt && <DsFreshness at={updatedAt} by={updatedBy} stale={stale} />}
      {helpHref && (
        <a href={helpHref} className={HELP}>
          {helpLabel}
        </a>
      )}
      {onHelp && (
        <button type="button" aria-haspopup="dialog" onClick={onHelp} className={HELP}>
          {helpLabel}
        </button>
      )}
      {children}
    </div>
  );
}
