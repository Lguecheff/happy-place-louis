import { cn } from "@/lib/utils";
import { DsButton } from "./ds-button";
import { DsIcon } from "./ds-icon";

export type DsSaveState = "idle" | "saving" | "saved" | "error";

type DsSaveStatusProps = {
  state: DsSaveState;
  /** Heure du dernier enregistrement réussi (état « saved »). */
  at?: Date;
  /** Bouton « Réessayer », affiché seulement en cas d'échec. */
  onRetry?: () => void;
  className?: string;
};

const TIME = new Intl.DateTimeFormat("fr-FR", { hour: "2-digit", minute: "2-digit" });

/**
 * État d'un enregistrement automatique. La zone est toujours présente (aria-live polie),
 * même vide, pour que chaque changement soit annoncé.
 */
export function DsSaveStatus({ state, at, onRetry, className }: DsSaveStatusProps) {
  return (
    <div className={cn("flex flex-wrap items-center gap-xs", className)}>
      <p
        role="status"
        aria-live="polite"
        className={cn(
          "inline-flex items-center gap-1 font-label-md text-label-md normal-case tracking-normal",
          state === "error" ? "text-error" : "text-on-surface-variant",
        )}
      >
        {state === "saving" && (
          <>
            <DsIcon name="progress_activity" className="animate-spin text-base" />
            Enregistrement…
          </>
        )}
        {state === "saved" && at && (
          <>
            <DsIcon name="cloud_done" className="text-base" />
            <span>
              Enregistré à <time dateTime={at.toISOString()}>{TIME.format(at)}</time>
            </span>
          </>
        )}
        {state === "error" && (
          <>
            <DsIcon name="error" className="text-base" />
            Échec de l'enregistrement
          </>
        )}
      </p>
      {state === "error" && onRetry && (
        <DsButton variant="link" icon="refresh" onClick={onRetry}>
          Réessayer
        </DsButton>
      )}
    </div>
  );
}
