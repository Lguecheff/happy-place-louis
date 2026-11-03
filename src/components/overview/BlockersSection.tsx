import { useQuery } from "@tanstack/react-query";
import {
  DS_INPUT,
  DsBadge,
  DsButton,
  DsEmptyState,
  DsField,
  DsFreshness,
  DsIcon,
  DsListItem,
  DsSection,
  DsStaleBadge,
} from "@/components/ds";
import {
  blockerReminded,
  blockerStaleDays,
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

/** Badge « À vérifier » et date de mise à jour d'un point bloquant. */
export function BlockerFreshness({ blocker: b }: { blocker: Blocker }) {
  const staleDays = blockerStaleDays(b);
  return (
    <span className="flex flex-wrap items-center gap-xs">
      {staleDays != null && <DsStaleBadge days={staleDays} />}
      <DsFreshness at={b.updated_at} by={b.updated_by_name} />
    </span>
  );
}

/**
 * Point à vérifier : « Relancé le JJ/MM/AAAA par <nom> » pour tous tant que le point n'a pas
 * bougé depuis la relance ; sinon le bouton « Relancer équipes », si le lecteur peut relancer.
 */
function BlockerReminder({
  blocker: b,
  pending,
  onRemind,
}: {
  blocker: Blocker;
  pending?: boolean;
  onRemind?: () => void;
}) {
  if (blockerStaleDays(b) == null) return null;
  if (blockerReminded(b)) {
    return (
      <p className="inline-flex items-center gap-1 font-label-md text-label-md normal-case tracking-normal text-on-surface-variant">
        <DsIcon name="campaign" className="text-base" />
        Relancé le {formatDay(b.reminded_at as string)}
        {b.reminded_by_name && ` par ${b.reminded_by_name}`}
      </p>
    );
  }
  if (!onRemind) return null;
  return (
    <DsButton
      icon="campaign"
      pending={pending}
      onClick={onRemind}
      className="self-start"
      aria-label={`Relancer les équipes du point ${b.title}`}
    >
      Relancer équipes
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
  onRemind,
  reminding,
}: {
  blocker: Blocker;
  myTeams: string[];
  canEdit: boolean;
  onOpen: OpenBlocker;
  onStatusChange: (status: string) => void;
  /** Sans valeur, le lecteur ne peut pas relancer les équipes de ce point. */
  onRemind?: () => void;
  reminding?: boolean;
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
      <BlockerReminder blocker={b} pending={reminding} onRemind={onRemind} />
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
  canRemind,
  onRemind,
  remindingId,
}: {
  blockers: { data?: Blocker[]; isError: boolean };
  /** Équipes du lecteur : la sienne passe en premier dans « Data +2 ». */
  myTeams?: string[];
  /** Admin : tous les points ; manager : ceux qui le concernent. La base vérifie le même droit. */
  canEdit: boolean | ((blocker: Blocker) => boolean);
  onOpen: OpenBlocker;
  onStatusChange: (id: string, status: string) => void;
  onOpenArchive: () => void;
  /** Admin : tous les points ; manager : ceux qui ne le concernent pas. La base vérifie le même droit. */
  canRemind?: (blocker: Blocker) => boolean;
  onRemind?: (blocker: Blocker) => void;
  remindingId?: string | null;
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
            canEdit={typeof canEdit === "function" ? canEdit(b) : canEdit}
            onOpen={onOpen}
            onStatusChange={(status) => onStatusChange(b.id, status)}
            onRemind={onRemind && canRemind?.(b) ? () => onRemind(b) : undefined}
            reminding={remindingId === b.id}
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
