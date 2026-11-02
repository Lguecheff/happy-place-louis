import { Linkify } from "@/components/linkify";
import { BlockerBadges } from "@/components/overview/BlockersSection";
import { formatDay } from "@/components/overview/overview-utils";
import { ReaderDialog } from "@/components/reader-dialog";
import type { Blocker } from "@/lib/dashboard";

/** Fenêtre de lecture d'un point bloquant, résolu compris (lecture seule). */
export function BlockerReader({
  blocker: b,
  onClose,
  onCloseAutoFocus,
}: {
  blocker: Blocker | null;
  onClose: () => void;
  onCloseAutoFocus?: (event: Event) => void;
}) {
  if (!b) return null;
  return (
    <ReaderDialog
      title={b.title}
      subtitle={`Créé le ${formatDay(b.created_at)} · Dernière modification le ${formatDay(b.updated_at)}`}
      onClose={onClose}
      onCloseAutoFocus={onCloseAutoFocus}
    >
      <div className="flex flex-wrap items-center gap-xs">
        <BlockerBadges blocker={b} />
      </div>
      {b.description ? (
        <p className="font-body-md text-body-md text-on-surface whitespace-pre-line wrap-anywhere">
          <Linkify text={b.description} />
        </p>
      ) : (
        <p className="font-body-md text-body-md text-on-surface-variant">Aucune description.</p>
      )}
    </ReaderDialog>
  );
}
