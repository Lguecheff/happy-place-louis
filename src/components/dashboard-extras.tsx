import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { AttachmentLink } from "@/components/attachment-link";
import { SubmissionPreview, formatExactDate } from "@/components/expandable-card";
import { ManageIcon } from "@/components/manage/crud-ui";
import { DS_INPUT } from "@/components/ds";
import { cn } from "@/lib/utils";
import { statusLabel } from "@/components/overview/overview-utils";
import { StatusChip } from "@/components/submission-status-thread";
import { ACTION_BUTTON, StatusMenu, type Status } from "@/components/status-actions";
import {
  fetchManagedSubmissions,
  fetchValidatedSubmissions,
  type Submission,
} from "@/lib/dashboard";

/** Peut lire la pièce jointe : mêmes règles que le stockage (auteur, manager de l'équipe, admin). */
export function canReadAttachment(
  s: Submission,
  ctx: { role: string | null | undefined; email: string; managerTeams: string[] },
) {
  if (ctx.role === "admin") return true;
  if (ctx.email && (s.submitted_by_email ?? "").toLowerCase() === ctx.email.toLowerCase()) return true;
  return ctx.role === "manager" && ctx.managerTeams.includes(s.team);
}

const PAGE = 10;

export function ValidatedSubmissions({
  role,
  email,
  managerTeams,
  onRead,
}: {
  role: string | null | undefined;
  email: string;
  managerTeams: string[];
  onRead: (s: Submission) => void;
}) {
  const q = useQuery({ queryKey: ["submissions", "validated"], queryFn: fetchValidatedSubmissions, retry: false });
  const [team, setTeam] = useState("");
  const [limit, setLimit] = useState(PAGE);
  const teams = useMemo(
    () => [...new Set((q.data ?? []).map((s) => s.team))].sort((a, b) => a.localeCompare(b, "fr")),
    [q.data],
  );
  const filtered = (q.data ?? []).filter((s) => !team || s.team === team);
  const shown = filtered.slice(0, limit);

  return (
    <div className="min-w-0">
      <div className="flex flex-wrap items-center justify-between gap-sm mb-md">
        <h3 className="font-label-md text-label-md normal-case tracking-normal text-on-surface-variant">Demandes validées</h3>
        <label className="flex items-center gap-xs font-label-md text-label-md normal-case tracking-normal text-on-surface-variant min-w-0">
          <span className="sr-only">Filtrer par équipe</span>
          <select
            aria-label="Filtrer par équipe"
            value={team}
            onChange={(e) => { setTeam(e.target.value); setLimit(PAGE); }}
            className={cn(DS_INPUT, "w-auto max-w-full")}
          >
            <option value="">Toutes les équipes</option>
            {teams.map((t) => <option key={t} value={t}>{t}</option>)}
          </select>
        </label>
      </div>
      {q.isLoading && <p className="text-body-sm text-on-surface-variant">Chargement…</p>}
      {q.isError && <p className="text-body-sm text-error">Les demandes validées sont indisponibles.</p>}
      {q.data && filtered.length === 0 && (
        <p className="text-body-sm text-on-surface-variant italic">Aucune demande validée pour le moment.</p>
      )}
      <div className="grid gap-xs md:grid-cols-2">
        {shown.map((s) => (
          <div key={s.id} className="p-sm border border-outline-variant bg-card min-w-0 overflow-hidden space-y-xs">
            <p className="font-label-md text-label-md normal-case tracking-normal text-on-surface-variant wrap-anywhere">
              <span className="text-primary font-bold">{s.author_name}</span> · {s.team} ·{" "}
              {s.validated_at ? `Validée le ${formatExactDate(s.validated_at)}` : `Créée le ${formatExactDate(s.created_at)}`}
            </p>
            <SubmissionPreview content={s.content} onOpen={() => onRead(s)} />
            {s.attachment_path &&
              (canReadAttachment(s, { role, email, managerTeams }) ? (
                <AttachmentLink path={s.attachment_path} name={s.attachment_name} />
              ) : (
                <p className="font-label-md text-label-md normal-case tracking-normal text-on-surface-variant italic">Pièce jointe réservée à l'équipe</p>
              ))}
          </div>
        ))}
      </div>
      {filtered.length > limit && (
        <button
          type="button"
          onClick={() => setLimit((l) => l + PAGE)}
          className="mt-md min-h-11 font-label-md text-label-md normal-case tracking-normal text-primary underline"
        >
          Afficher plus ({filtered.length - limit} restantes)
        </button>
      )}
    </div>
  );
}

const MANAGED_STATUSES = ["en attente", "validée", "refusée", "clôturée"] as const;

/** Toutes les demandes de ses équipes, quel que soit le statut : le manager ouvre une demande pour en corriger le statut. */
export function ManagedSubmissions({
  onRead,
  onThread,
  onChangeStatus,
}: {
  onRead: (s: Submission) => void;
  onThread: (s: Submission) => void;
  onChangeStatus: (s: Submission, status: Status) => void;
}) {
  const q = useQuery({ queryKey: ["submissions", "managed"], queryFn: fetchManagedSubmissions, retry: false });
  const [status, setStatus] = useState("");
  const [limit, setLimit] = useState(PAGE);
  const filtered = (q.data ?? []).filter((s) => !status || s.status === status);
  const shown = filtered.slice(0, limit);

  return (
    <div className="min-w-0">
      <div className="flex flex-wrap items-center justify-between gap-sm mb-md">
        <h3 className="font-label-md text-label-md normal-case tracking-normal text-on-surface-variant">Suivi des demandes</h3>
        <select
          aria-label="Filtrer par statut"
          value={status}
          onChange={(e) => {
            setStatus(e.target.value);
            setLimit(PAGE);
          }}
          className={cn(DS_INPUT, "w-auto max-w-full")}
        >
          <option value="">Tous les statuts</option>
          {MANAGED_STATUSES.map((st) => (
            <option key={st} value={st}>
              {statusLabel(st)}
            </option>
          ))}
        </select>
      </div>
      {q.isLoading && <p className="text-body-sm text-on-surface-variant">Chargement…</p>}
      {q.isError && <p className="text-body-sm text-error">Les demandes sont indisponibles.</p>}
      {q.data && filtered.length === 0 && (
        <p className="text-body-sm text-on-surface-variant italic">Aucune demande pour ce statut.</p>
      )}
      <div className="grid gap-xs md:grid-cols-2">
        {shown.map((s) => (
          <div key={s.id} className="p-sm border border-outline-variant bg-card min-w-0 space-y-xs">
            <StatusChip status={s.status} />
            <p className="font-label-md text-label-md normal-case tracking-normal text-on-surface-variant wrap-anywhere">
              <span className="text-primary font-bold">{s.author_name}</span> · {s.team} ·{" "}
              {formatExactDate(s.created_at)}
            </p>
            <SubmissionPreview content={s.content} onOpen={() => onRead(s)} />
            <div className="flex flex-wrap items-center gap-xs pt-xs">
              <button
                type="button"
                aria-haspopup="dialog"
                onClick={() => onThread(s)}
                className={ACTION_BUTTON}
              >
                <ManageIcon name="history" /> Voir le détail
              </button>
              <StatusMenu id={s.id} current={s.status} onPick={(st) => onChangeStatus(s, st)} />
            </div>
          </div>
        ))}
      </div>
      {filtered.length > limit && (
        <button
          type="button"
          onClick={() => setLimit((l) => l + PAGE)}
          className="mt-md min-h-11 font-label-md text-label-md normal-case tracking-normal text-primary underline"
        >
          Afficher plus ({filtered.length - limit} restantes)
        </button>
      )}
    </div>
  );
}
