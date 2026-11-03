import { useQuery } from "@tanstack/react-query";
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
  formatDay,
  severityLabel,
  statusLabel,
  teamsSummary,
} from "@/components/overview/overview-utils";
import { ReaderDialog } from "@/components/reader-dialog";
import { fetchResolvedBlockers, type Blocker } from "@/lib/dashboard";

const BLOCKER_STATUSES = ["OUVERT", "EN COURS", "SURVEILLANCE", "RÉSOLU"];

/** Ouvre un point dans sa fenêtre de lecture ; `trigger` reçoit le focus à la fermeture. */
export type OpenBlocker = (blocker: Blocker, trigger: HTMLElement) => void;

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

export function BlockerTitle({ blocker: b, myTeams }: { blocker: Blocker; myTeams: string[] }) {
  return (
    <>
      <span className="mb-xs flex flex-wrap items-center gap-xs">
        <BlockerBadges blocker={b} />
        <DsBadge>{teamsSummary(b.teams, myTeams)}</DsBadge>
      </span>
      {b.title}
    </>
  );
}

function BlockerRow({
  blocker: b,
  myTeams,
  canEdit,
  onOpen,
  onStatusChange,
}: {
  blocker: Blocker;
  myTeams: string[];
  canEdit: boolean;
  onOpen: OpenBlocker;
  onStatusChange: (status: string) => void;
}) {
  const critical = b.severity === "critical";
  const stale = critical && daysSince(b.updated_at) > BLOCKER_STALE_DAYS;
  const selectId = `statut-point-${b.id}`;
  return (
    <DsListItem
      className={critical ? "accent-bar" : undefined}
      title={<BlockerTitle blocker={b} myTeams={myTeams} />}
      meta={b.description}
      opensDialog
      onClick={(e) => onOpen(b, e.currentTarget)}
    >
      <DsFreshness at={b.updated_at} stale={stale} />
      {/* Hors du bouton de la ligne : changer le statut n'ouvre pas la fenêtre. */}
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
  myTeams = [],
  canEdit,
  onOpen,
  onStatusChange,
  onOpenArchive,
}: {
  blockers: { data?: Blocker[]; isError: boolean };
  /** Équipes du lecteur : la sienne passe en premier dans « Data +2 ». */
  myTeams?: string[];
  canEdit: boolean;
  onOpen: OpenBlocker;
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
            myTeams={myTeams}
            canEdit={canEdit}
            onOpen={onOpen}
            onStatusChange={(status) => onStatusChange(b.id, status)}
          />
        ))}
      </div>
    </DsSection>
  );
}

/** Fenêtre « Archive des points bloquants » : points résolus, chacun s'ouvre en lecture. */
export function BlockerArchive({
  open,
  myTeams = [],
  onOpen,
  onClose,
}: {
  open: boolean;
  myTeams?: string[];
  onOpen: OpenBlocker;
  onClose: () => void;
}) {
  const q = useQuery({
    queryKey: ["blockers", "resolved"],
    queryFn: fetchResolvedBlockers,
    enabled: open,
    retry: false,
  });
  if (!open) return null;
  return (
    <ReaderDialog
      title="Archive des points bloquants"
      subtitle="Points résolus, du plus récent au plus ancien"
      onClose={onClose}
    >
      <div className="space-y-xs">
        {q.isLoading && (
          <p className="font-body-sm text-body-sm text-on-surface-variant">Chargement…</p>
        )}
        {q.isError && (
          <p className="font-body-sm text-body-sm text-error">L'archive est indisponible.</p>
        )}
        {q.data?.length === 0 && <DsEmptyState>Aucun point bloquant résolu.</DsEmptyState>}
        {q.data?.map((b) => (
          <DsListItem
            key={b.id}
            title={<BlockerTitle blocker={b} myTeams={myTeams} />}
            meta={`Mis à jour le ${formatDay(b.updated_at)}`}
            opensDialog
            onClick={(e) => onOpen(b, e.currentTarget)}
          />
        ))}
      </div>
    </ReaderDialog>
  );
}
