import { timeAgo } from "@/lib/dashboard";
import { cn } from "@/lib/utils";
import { DsIcon } from "./ds-icon";
import { DsTooltip } from "./ds-tooltip";
import { DS_FOCUS } from "./focus";

const FULL_DATE = new Intl.DateTimeFormat("fr-FR", {
  dateStyle: "full",
  timeStyle: "short",
  timeZone: "Europe/Paris",
});

type DsFreshnessProps = {
  /** Date ISO de la dernière mise à jour. */
  at: string;
  /** Auteur de la dernière mise à jour (« Automatique » sans utilisateur) ; vide, la mention s'arrête à la date. */
  by?: string | null;
  /** Donnée trop ancienne : texte en couleur d'alerte, icône d'avertissement et mention pour les lecteurs d'écran. */
  stale?: boolean;
  /** Dernière modification = une confirmation : « Confirmé à jour » au lieu de « Mis à jour ». */
  confirmed?: boolean;
  className?: string;
};

export function DsFreshness({ at, by, stale, confirmed, className }: DsFreshnessProps) {
  const author = by?.trim();
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
      {/* Date complète au survol et au focus clavier. */}
      <DsTooltip
        content={
          <span className="font-body-sm text-body-sm">{FULL_DATE.format(new Date(at))}</span>
        }
      >
        <time dateTime={at} tabIndex={0} className={cn("cursor-help", DS_FOCUS)}>
          {confirmed ? "Confirmé à jour" : "Mis à jour"} {timeAgo(at)}
          {author && ` par ${author}`}
        </time>
      </DsTooltip>
    </p>
  );
}
