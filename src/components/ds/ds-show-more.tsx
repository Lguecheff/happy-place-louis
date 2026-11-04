/** Sous une liste : « N sur M affichées », « Voir moins » et « Voir plus » (US24). Voir `useShowMore`. */
import { useEffect, useRef } from "react";
import { cn } from "@/lib/utils";
import { DsButton } from "./ds-button";

export function DsShowMore({
  shown,
  total,
  announce = "",
  label,
  onMore,
  canLess = false,
  onLess,
  pending = false,
  error = false,
  onRetry,
  className,
}: {
  shown: number;
  total: number;
  /** Texte annoncé aux lecteurs d'écran (fourni par `useShowMore`). */
  announce?: string;
  /** Nom lu du bouton, qui commence par « Voir plus » (ex. « Voir plus d'actus »). */
  label: string;
  onMore: () => void;
  /** Plus que la première tranche est affiché (fourni par `useShowMore`). */
  canLess?: boolean;
  /** Retire la dernière tranche ; sans valeur, pas de « Voir moins ». Son nom lu remplace « Voir plus » par « Voir moins » dans `label`. */
  onLess?: () => void;
  /** Suite en cours de chargement depuis la base. */
  pending?: boolean;
  /** Échec du chargement de la suite. */
  error?: boolean;
  onRetry?: () => void;
  className?: string;
}) {
  const retryBox = useRef<HTMLDivElement>(null);
  const wasError = useRef(error);

  // Le focus va sur « Réessayer » quand l'échec survient, pas quand la page s'ouvre déjà en échec.
  useEffect(() => {
    if (error && !wasError.current) retryBox.current?.querySelector("button")?.focus();
    wasError.current = error;
  }, [error]);

  const live = error ? "Impossible de charger la suite." : pending ? "Chargement…" : announce;

  return (
    <div className={cn("flex flex-wrap items-center justify-between gap-sm pt-xs", className)}>
      <p className="font-label-md text-label-md text-on-surface-variant">
        {shown} sur {total} affichées
      </p>
      <div className="flex flex-wrap items-center gap-sm">
        {onLess && canLess && !pending && (
          <DsButton aria-label={label.replace("Voir plus", "Voir moins")} onClick={onLess}>
            Voir moins
          </DsButton>
        )}
        {error ? (
          <div ref={retryBox} className="flex flex-wrap items-center gap-sm">
            <p className="font-body-sm text-body-sm text-error">Impossible de charger la suite.</p>
            <DsButton onClick={onRetry ?? onMore}>Réessayer</DsButton>
          </div>
        ) : (
          shown < total && (
            <DsButton pending={pending} aria-label={pending ? undefined : label} onClick={onMore}>
              {pending ? "Chargement…" : "Voir plus"}
            </DsButton>
          )
        )}
      </div>
      <p className="sr-only" aria-live="polite">
        {live}
      </p>
    </div>
  );
}
