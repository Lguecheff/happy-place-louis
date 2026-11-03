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
  DsStaleBadge,
} from "@/components/ds";
import {
  blockerStaleDays,
  formatDay,
  isConfirmed,
  severityLabel,
  statusLabel,
  teamsSummary,
} from "@/components/overview/overview-utils";
import { ReaderDialog } from "@/components/reader-dialog";
import { fetchResolvedBlockers, type Blocker } from "@/lib/dashboard";

const BLOCKER_STATUSES = ["OUVERT", "EN COURS", "SURVEILLANCE", "RÉSOLU"];

/** Ouvre un point dans sa fenêtre de lecture ; `trigger` reçoit le focus à la fermeture. */
export type OpenBlocker = (blocker: Blocker, trigger: HTMLElement) => void;

/** Badge « À vérifier » et date de mise à jour (ou de confirmation) d'un point bloquant. */
export function BlockerFreshness({ blocker: b }: { blocker: Blocker }) {
  const staleDays = blockerStaleDays(b);
  return (
    <span className="flex flex-wrap items-center gap-xs">
      {staleDays != null && <DsStaleBadge days={staleDays} />}
      <DsFreshness at={b.updated_at} by={b.updated_by_name} confirmed={isConfirmed(b)} />
    </span>
  );
}

/** « Confirmer à jour », affiché seulement sur un point à vérifier. */
export function ConfirmUpToDate({
  pending,
  onConfirm,
}: {
  pending?: boolean;
  onConfirm: () => void;
}) {
  return (
    <DsButton icon="done" pending={pending} onClick={onConfirm} className="self-start">
      Confirmer à jour
    </DsButton>
  );
}

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
  onConfirm,
  confirming,
}: {
  blocker: Blocker;
  myTeams: string[];
  canEdit: boolean;
  onOpen: OpenBlocker;
  onStatusChange: (status: string) => void;
  /** Sans valeur, le lecteur ne peut pas confirmer ce point. */
  onConfirm?: () => void;
  confirming?: boolean;
}) {
  const critical = b.severity === "critical";
  const selectId = `statut-point-${b.id}`;
  return (
    <DsListItem
      className={critical ? "accent-bar" : undefined}
      title={<BlockerTitle blocker={b} myTeams={myTeams} />}
      meta={b.description}
      opensDialog
      onClick={(e) => onOpen(b, e.currentTarget)}
    >
      <BlockerFreshness blocker={b} />
      {onConfirm && blockerStaleDays(b) != null && (
        <ConfirmUpToDate pending={confirming} onConfirm={onConfirm} />
      )}
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
  canConfirm,
  onConfirm,
  confirmingId,
}: {
  blockers: { data?: Blocker[]; isError: boolean };
  /** Équipes du lecteur : la sienne passe en premier dans « Data +2 ». */
  myTeams?: string[];
  canEdit: boolean;
  onOpen: OpenBlocker;
  onStatusChange: (id: string, status: string) => void;
  onOpenArchive: () => void;
  /** Admin : tous les points ; manager : ceux de ses équipes. La base vérifie le même droit. */
  canConfirm?: (blocker: Blocker) => boolean;
  onConfirm?: (blocker: Blocker) => void;
  confirmingId?: string | null;
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
            onConfirm={onConfirm && canConfirm?.(b) ? () => onConfirm(b) : undefined}
            confirming={confirmingId === b.id}
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
