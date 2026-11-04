import { DsBadge } from "@/components/ds";
import { LONG_WAIT_DAYS, isLongWait } from "@/components/overview/overview-utils";
import type { Submission } from "@/lib/dashboard";

/** Badge « Plus de LONG_WAIT_DAYS jours » (7) d'une demande en attente sans réponse (US22) ; rien sinon. */
export function LongWaitBadge({ submission }: { submission: Submission }) {
  if (!isLongWait(submission)) return null;
  return (
    <p className="flex">
      <DsBadge variant="watch" icon="hourglass_bottom">
        Plus de {LONG_WAIT_DAYS} jours
      </DsBadge>
    </p>
  );
}
