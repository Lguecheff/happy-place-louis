import * as DialogPrimitive from "@radix-ui/react-dialog";
import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { AttachmentLink } from "@/components/attachment-link";
import { SubmissionPreview, formatExactDate } from "@/components/expandable-card";
import { ManageIcon } from "@/components/manage/crud-ui";
import { DS_INPUT } from "@/components/ds";
import { cn } from "@/lib/utils";
import { severityLabel, statusLabel } from "@/components/overview/overview-utils";
import { StatusChip } from "@/components/submission-status-thread";
import { ACTION_BUTTON, StatusMenu, type Status } from "@/components/status-actions";
import {
  fetchManagedSubmissions,
  fetchResolvedBlockers,
  fetchValidatedSubmissions,
  type Submission,
} from "@/lib/dashboard";

/** Fenêtre « Archive des points bloquants » (lecture seule, statut Résolu). */
export function BlockerArchive({ open, onClose }: { open: boolean; onClose: () => void }) {
  const q = useQuery({ queryKey: ["blockers", "resolved"], queryFn: fetchResolvedBlockers, enabled: open, retry: false });
  return (
    <DialogPrimitive.Root open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogPrimitive.Portal>
        <DialogPrimitive.Overlay className="fixed inset-0 z-50 bg-black/50" />
        <DialogPrimitive.Content className="fixed z-50 inset-0 md:inset-auto md:left-1/2 md:top-1/2 md:-translate-x-1/2 md:-translate-y-1/2 w-full md:w-[min(48rem,calc(100vw-2rem))] h-dvh md:h-auto md:max-h-[85vh] flex flex-col bg-surface-container-lowest border border-outline shadow-lg focus:outline-none">
          <div className="flex items-start justify-between gap-sm border-b border-outline-variant p-md">
            <div className="min-w-0">
              <DialogPrimitive.Title className="font-headline-sm text-headline-sm text-primary">
                Archive des points bloquants
              </DialogPrimitive.Title>
              <DialogPrimitive.Description className="font-label-md text-label-md normal-case tracking-normal text-on-surface-variant">
                Points résolus, du plus récent au plus ancien
              </DialogPrimitive.Description>
            </div>
            <DialogPrimitive.Close aria-label="Fermer" className="inline-flex size-11 shrink-0 items-center justify-center text-on-surface-variant hover:text-primary focus:outline-none focus-visible:ring-2 focus-visible:ring-primary">
              <span aria-hidden="true" className="material-symbols-outlined">close</span>
            </DialogPrimitive.Close>
          </div>
          <div className="flex-1 overflow-y-auto p-md space-y-sm">
            {q.isLoading && <p className="text-body-sm text-on-surface-variant">Chargement…</p>}
            {q.isError && <p className="text-body-sm text-error">L'archive est indisponible.</p>}
            {q.data?.length === 0 && (
              <p className="text-body-sm text-on-surface-variant italic">Aucun point bloquant résolu.</p>
            )}
            {q.data?.map((b) => (
              <div key={b.id} className="bg-card border border-outline-variant p-sm min-w-0">
                <p className="font-body-md text-primary font-bold wrap-anywhere">{b.title}</p>
                {b.description && (
                  <p className="text-body-sm text-on-surface-variant whitespace-pre-line wrap-anywhere">{b.description}</p>
                )}
                <div className="flex flex-wrap items-center gap-sm mt-xs font-label-md text-label-md normal-case tracking-normal">
                  <span className="bg-surface-container-highest px-xs py-0.5">{statusLabel(b.department)}</span>
                  <span className="text-on-surface-variant">Gravité : {severityLabel(b.severity)}</span>
                  <span className="text-on-surface-variant">Mis à jour le {formatExactDate(b.updated_at)}</span>
                </div>
              </div>
            ))}
          </div>
        </DialogPrimitive.Content>
      </DialogPrimitive.Portal>
    </DialogPrimitive.Root>
  );
}

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
                <ManageIcon name="history" /> Voir le suivi
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
