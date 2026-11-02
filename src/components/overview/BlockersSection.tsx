import {
  DS_INPUT,
  DsBadge,
  DsButton,
  DsEmptyState,
  DsField,
  DsFreshness,
  DsListItem,
  DsSection,
} from "@/components/ds";
import {
  BLOCKER_STALE_DAYS,
  daysSince,
  severityLabel,
  statusLabel,
} from "@/components/overview/overview-utils";
import type { Blocker } from "@/lib/dashboard";

const BLOCKER_STATUSES = ["OUVERT", "EN COURS", "SURVEILLANCE", "RÉSOLU"];

/** Sévérité et statut d'un point bloquant, avec « Archivé » une fois résolu. */
export function BlockerBadges({ blocker: b }: { blocker: Blocker }) {
  const critical = b.severity === "critical";
  return (
    <>
      <DsBadge variant={critical ? "critical" : "watch"} icon={critical ? "error" : "warning"}>
        {severityLabel(b.severity)}
      </DsBadge>
      <DsBadge variant="status">{statusLabel(b.status)}</DsBadge>
      {b.status === "RÉSOLU" && <DsBadge>Archivé</DsBadge>}
    </>
  );
}

function BlockerRow({
  blocker: b,
  canEdit,
  onStatusChange,
}: {
  blocker: Blocker;
  canEdit: boolean;
  onStatusChange: (status: string) => void;
}) {
  const critical = b.severity === "critical";
  const stale = critical && daysSince(b.updated_at) > BLOCKER_STALE_DAYS;
  const selectId = `statut-point-${b.id}`;
  return (
    <DsListItem
      className={critical ? "accent-bar" : undefined}
      title={
        <>
          <span className="mb-xs flex flex-wrap items-center gap-xs">
            <BlockerBadges blocker={b} />
            <DsBadge>{statusLabel(b.department)}</DsBadge>
          </span>
          {b.title}
        </>
      }
      meta={b.description}
    >
      <DsFreshness at={b.updated_at} stale={stale} />
      {canEdit && (
        <DsField id={selectId} label={`Changer le statut de ${b.title}`}>
          <select
            id={selectId}
            className={DS_INPUT}
            value={b.status}
            onChange={(e) => onStatusChange(e.target.value)}
          >
            {BLOCKER_STATUSES.map((status) => {
              const locked = status === "RÉSOLU" && b.status === "OUVERT";
              return (
                <option
                  key={status}
                  value={status}
                  disabled={locked}
                  title={locked ? "Passe d'abord par En cours" : undefined}
                >
                  {statusLabel(status)}
                </option>
              );
            })}
          </select>
        </DsField>
      )}
    </DsListItem>
  );
}

export function BlockersSection({
  blockers,
  canEdit,
  onStatusChange,
  onOpenArchive,
}: {
  blockers: { data?: Blocker[]; isError: boolean };
  canEdit: boolean;
  onStatusChange: (id: string, status: string) => void;
  onOpenArchive: () => void;
}) {
  // Les points critiques d'abord ; le tri de la base est conservé à gravité égale.
  const rows = [...(blockers.data ?? [])].sort(
    (a, b) => Number(b.severity === "critical") - Number(a.severity === "critical"),
  );
  return (
    <DsSection
      id="blocages"
      title="Points bloquants"
      action={
        <DsButton variant="link" className="px-0" aria-haspopup="dialog" onClick={onOpenArchive}>
          Voir l'archive
        </DsButton>
      }
    >
      <div className="space-y-xs">
        {blockers.isError && (
          <p className="font-body-sm text-body-sm text-error">
            Les points bloquants sont indisponibles.
          </p>
        )}
        {blockers.data?.length === 0 && <DsEmptyState>Aucun point bloquant en cours.</DsEmptyState>}
        {rows.map((b) => (
          <BlockerRow
            key={b.id}
            blocker={b}
            canEdit={canEdit}
            onStatusChange={(status) => onStatusChange(b.id, status)}
          />
        ))}
      </div>
    </DsSection>
  );
}
