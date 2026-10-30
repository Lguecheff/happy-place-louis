import { useQuery } from "@tanstack/react-query";
import { useEffect, type ReactNode } from "react";
import { ManageIcon, Modal } from "@/components/manage/crud-ui";
import {
  fetchSubmissionHistory,
  type Submission,
  type SubmissionStatusHistory,
} from "@/lib/dashboard";

export type ThreadStep = Pick<
  SubmissionStatusHistory,
  | "id"
  | "old_status"
  | "new_status"
  | "changed_by_email"
  | "changed_by_name"
  | "is_automatic"
  | "rejection_category"
  | "rejection_note"
  | "changed_at"
>;

const dateTime = new Intl.DateTimeFormat("fr-FR", { dateStyle: "long", timeStyle: "short" });

/** Étapes de la plus récente à la plus ancienne. */
export function sortSteps(steps: ThreadStep[]): ThreadStep[] {
  return [...steps].sort(
    (a, b) => new Date(b.changed_at).getTime() - new Date(a.changed_at).getTime(),
  );
}

function authorLabel(s: ThreadStep): string {
  if (s.is_automatic) return "Automatique";
  return s.changed_by_name ?? s.changed_by_email ?? "Utilisateur supprimé";
}

function statusChipClass(status: string): string {
  if (status === "validée") return "bg-secondary-fixed text-primary";
  if (status === "refusée") return "bg-error-container text-on-error-container";
  if (status === "clôturée") return "bg-primary text-on-primary";
  return "bg-surface-container-high text-primary";
}

export function StatusChip({ status }: { status: string }) {
  return (
    <span
      className={`inline-block px-xs py-1 font-label-sm text-label-sm uppercase ${statusChipClass(status)}`}
    >
      {status}
    </span>
  );
}

/** Fil vertical en lecture seule : une étape par changement de statut. */
export function StatusThread({ steps }: { steps: ThreadStep[] }) {
  return (
    <ol
      aria-label="Étapes de la demande, de la plus récente à la plus ancienne"
      className="border-l border-outline ml-xs"
    >
      {steps.map((s) => {
        const creation = s.old_status === null;
        return (
          <li key={s.id} className="relative pl-md pb-md last:pb-0">
            <span
              aria-hidden="true"
              className="absolute -left-[5px] top-[7px] h-[9px] w-[9px] border border-outline bg-surface-container-lowest"
            />
            <div className="flex flex-wrap items-center gap-xs">
              <StatusChip status={s.new_status} />
              {creation && (
                <span className="font-label-sm text-label-sm uppercase text-on-surface-variant">
                  Création
                </span>
              )}
            </div>
            <p className="mt-xs font-body-md text-body-md text-on-surface-variant">
              <time dateTime={s.changed_at} className="font-bold text-primary">
                {dateTime.format(new Date(s.changed_at))}
              </time>
            </p>
            <p className="font-body-md text-body-md text-on-surface-variant">
              {s.is_automatic ? "Changement " : creation ? "Créée par " : "Modifié par "}
              <span
                className={
                  s.is_automatic
                    ? "font-label-md text-label-md uppercase text-primary"
                    : "text-primary"
                }
              >
                {authorLabel(s)}
              </span>
            </p>
            {s.new_status === "refusée" && s.rejection_category && (
              <div className="mt-xs border-l-[3px] border-error bg-error-container p-xs text-on-error-container wrap-anywhere">
                <p className="font-label-md text-label-md uppercase">
                  Catégorie : {s.rejection_category}
                </p>
                {s.rejection_note && (
                  <p className="mt-1 font-body-md text-body-md whitespace-pre-line">
                    {s.rejection_note}
                  </p>
                )}
              </div>
            )}
          </li>
        );
      })}
    </ol>
  );
}

/** Fenêtre du fil (présentation seule) : focus dans la fenêtre, Échap pour fermer, focus rendu à la fermeture. */
export function SubmissionThreadView({
  content,
  team,
  steps,
  loading,
  error,
  readOnly = true,
  actions,
  onClose,
}: {
  content: string;
  team: string;
  steps: ThreadStep[];
  loading?: boolean;
  error?: boolean;
  /** Affiche la mention « Lecture seule » (par défaut). Les managers passent `false` et fournissent `actions`. */
  readOnly?: boolean;
  actions?: ReactNode;
  onClose: () => void;
}) {
  useEffect(() => {
    const trigger = document.activeElement as HTMLElement | null;
    document
      .querySelector<HTMLButtonElement>('[role="dialog"] button[aria-label="Fermer"]')
      ?.focus();
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("keydown", onKey);
      trigger?.focus();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <Modal title="Fil de la demande" onClose={onClose}>
      <div className="space-y-md">
        <div className="space-y-xs">
          <p className="font-body-md text-body-md text-on-surface wrap-anywhere">{content}</p>
          <p className="flex flex-wrap items-center gap-xs font-label-sm text-label-sm uppercase text-on-surface-variant">
            <span>{team}</span>
            {readOnly && (
              <>
                <span aria-hidden="true">·</span>
                <span className="inline-flex items-center gap-1">
                  <ManageIcon name="lock" className="!text-[14px]" /> Lecture seule
                </span>
              </>
            )}
          </p>
        </div>
        {actions}
        {loading && <p className="text-body-sm text-on-surface-variant">Chargement…</p>}
        {error && <p className="text-body-sm text-error">Impossible de charger le fil.</p>}
        {!loading && !error && steps.length <= 1 && (
          <p className="font-body-sm text-body-sm italic text-on-surface-variant">
            Aucun changement de statut depuis la création.
          </p>
        )}
        {steps.length > 0 && <StatusThread steps={steps} />}
      </div>
    </Modal>
  );
}

/** Fil d'une demande, lu dans la base (limité par les règles d'accès : seules les demandes lisibles ont un fil). */
export function SubmissionThreadModal({
  submission,
  onClose,
}: {
  submission: Submission;
  onClose: () => void;
}) {
  const q = useQuery({
    queryKey: ["submissions", "history", submission.id],
    queryFn: () => fetchSubmissionHistory(submission.id),
    retry: false,
  });
  return (
    <SubmissionThreadView
      content={submission.content}
      team={submission.team}
      steps={sortSteps(q.data ?? [])}
      loading={q.isLoading}
      error={q.isError}
      onClose={onClose}
    />
  );
}
