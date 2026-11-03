import { DsFreshness, DsIcon } from "@/components/ds";
import { Linkify } from "@/components/linkify";
import { BlockerBadges } from "@/components/overview/BlockersSection";
import { formatDay, teamsFull } from "@/components/overview/overview-utils";
import { ReaderDialog } from "@/components/reader-dialog";
import type { Blocker } from "@/lib/dashboard";

const LABEL = "font-label-md text-label-md normal-case tracking-normal text-on-surface-variant";

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
  const impact = b.impact?.trim();
  return (
    <ReaderDialog
      title={b.title}
      subtitle={`Créé le ${formatDay(b.created_at)}`}
      onClose={onClose}
      onCloseAutoFocus={onCloseAutoFocus}
    >
      <div className="flex flex-wrap items-center gap-xs">
        <BlockerBadges blocker={b} />
      </div>
      <DsFreshness at={b.updated_at} by={b.updated_by_name} />
      <dl>
        <dt className={LABEL}>{b.teams.length > 1 ? "Équipes concernées" : "Équipe concernée"}</dt>
        <dd className="font-body-md text-body-md text-on-surface wrap-anywhere">
          {teamsFull(b.teams)}
        </dd>
      </dl>
      {b.description ? (
        <p className="font-body-md text-body-md text-on-surface whitespace-pre-line wrap-anywhere">
          <Linkify text={b.description} />
        </p>
      ) : (
        <p className="font-body-md text-body-md text-on-surface-variant">Aucune description.</p>
      )}
      {impact && (
        <section
          aria-labelledby="point-impact"
          className="space-y-xs border border-outline-variant bg-surface-container p-sm"
        >
          <h3 id="point-impact" className={`flex items-center gap-xs ${LABEL}`}>
            <DsIcon name="person" />
            Ce que ça change pour toi
          </h3>
          <p className="font-body-md text-body-md text-on-surface whitespace-pre-line wrap-anywhere">
            {impact}
          </p>
        </section>
      )}
    </ReaderDialog>
  );
}
