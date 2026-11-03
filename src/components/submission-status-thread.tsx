import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useEffect, type ReactNode } from "react";
import { toast } from "sonner";
import { AttachmentLink } from "@/components/attachment-link";
import { DsBadge, DsButton, DsFreshness, DsStaleBadge, type DsBadgeVariant } from "@/components/ds";
import { Linkify } from "@/components/linkify";
import { ManageIcon, Modal } from "@/components/manage/crud-ui";
import { statusLabel, submissionStaleDays } from "@/components/overview/overview-utils";
import {
  confirmSubmissionUpToDate,
  fetchSubmissionHistory,
  fetchSubmissionVerifications,
  type Submission,
  type SubmissionStatusHistory,
  type SubmissionVerification,
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
> & {
  /** « Confirmer à jour » (US21) : ligne « Vérifiée par <nom> », sans changement de statut. */
  kind?: "verification";
};

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

function statusVariant(status: string): DsBadgeVariant {
  if (status === "validée") return "status";
  if (status === "refusée") return "critical";
  return "neutral";
}

export function StatusChip({ status }: { status: string }) {
  return <DsBadge variant={statusVariant(status)}>{statusLabel(status)}</DsBadge>;
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
        const verification = s.kind === "verification";
        return (
          <li key={s.id} className="relative pl-md pb-md last:pb-0">
            <span
              aria-hidden="true"
              className="absolute -left-[5px] top-[7px] h-[9px] w-[9px] border border-outline bg-surface-container-lowest"
            />
            <div className="flex flex-wrap items-center gap-xs">
              {verification ? (
                <DsBadge icon="done">Vérifiée à jour</DsBadge>
              ) : (
                <StatusChip status={s.new_status} />
              )}
              {creation && (
                <span className="font-label-md text-label-md normal-case tracking-normal text-on-surface-variant">
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
              {s.is_automatic
                ? "Changement "
                : creation
                  ? "Créée par "
                  : verification
                    ? "Par "
                    : "Modifié par "}
              <span
                className={
                  s.is_automatic
                    ? "font-label-md text-label-md normal-case tracking-normal text-primary"
                    : "text-primary"
                }
              >
                {authorLabel(s)}
              </span>
            </p>
            {s.new_status === "refusée" && s.rejection_category && (
              <div className="mt-xs border-l-[3px] border-error bg-error-container p-xs text-on-error-container wrap-anywhere">
                <p className="font-label-md text-label-md normal-case tracking-normal">
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

/**
 * Fraîcheur d'une demande, dans son détail seulement : badge « À vérifier » (clôturée depuis plus
 * d'un an), date de mise à jour, et « Confirmer à jour » si le lecteur peut confirmer.
 */
export function SubmissionUpToDate({
  status,
  updatedAt,
  verifiedBy,
  pending,
  onConfirm,
}: {
  status: string;
  /** Dernier changement de statut ou dernière confirmation. */
  updatedAt: string;
  /** Auteur de la dernière confirmation, si c'est la dernière mise à jour. */
  verifiedBy?: string | null;
  pending?: boolean;
  /** Auteur, membres et managers de l'équipe, admin ; sans valeur, pas de bouton. */
  onConfirm?: () => void;
}) {
  const staleDays = submissionStaleDays(status, updatedAt);
  return (
    <div className="flex flex-col gap-xs">
      <span className="flex flex-wrap items-center gap-xs">
        {staleDays != null && <DsStaleBadge days={staleDays} />}
        <DsFreshness at={updatedAt} by={verifiedBy} verified={verifiedBy !== undefined} />
      </span>
      {onConfirm && staleDays != null && (
        <DsButton icon="done" pending={pending} onClick={onConfirm} className="self-start">
          Confirmer à jour
        </DsButton>
      )}
    </div>
  );
}

/** Une confirmation, en ligne du fil. */
export function verificationStep(
  v: Pick<SubmissionVerification, "id" | "verified_by_name" | "verified_at">,
  status: string,
): ThreadStep {
  return {
    id: v.id,
    kind: "verification",
    old_status: status,
    new_status: status,
    changed_by_email: null,
    changed_by_name: v.verified_by_name,
    is_automatic: false,
    rejection_category: null,
    rejection_note: null,
    changed_at: v.verified_at,
  };
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
  follow,
  upToDate,
  attachment,
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
  /** Suivi de la demande (`FollowButton`), sous l'équipe. */
  follow?: ReactNode;
  /** Badge « À vérifier », date de mise à jour et « Confirmer à jour » (`SubmissionUpToDate`). */
  upToDate?: ReactNode;
  /** Pièce jointe (`AttachmentLink`), sous le texte. */
  attachment?: ReactNode;
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
    <Modal title="Détail de la demande" onClose={onClose}>
      <div className="space-y-md">
        <div className="space-y-xs">
          <p className="font-body-md text-body-md text-on-surface whitespace-pre-line wrap-anywhere">
            <Linkify text={content} />
          </p>
          <p className="flex flex-wrap items-center gap-xs font-label-md text-label-md normal-case tracking-normal text-on-surface-variant">
            <span>{team}</span>
            {readOnly && (
              <>
                <span aria-hidden="true">·</span>
                <span className="inline-flex items-center gap-1">
                  <ManageIcon name="lock" className="text-base" /> Lecture seule
                </span>
              </>
            )}
          </p>
          {attachment}
          {follow}
          {upToDate}
        </div>
        {actions}
        {loading && <p className="text-body-sm text-on-surface-variant">Chargement…</p>}
        {error && <p className="text-body-sm text-error">Impossible de charger le détail.</p>}
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

/** Détail d'une demande, lu dans la base (limité par les règles d'accès : seules les demandes lisibles ont un fil). */
export function SubmissionThreadModal({
  submission,
  actions,
  follow,
  canConfirm,
  showAttachment,
  onClose,
}: {
  submission: Submission;
  /** Actions de statut réservées aux managers : reçoivent le statut courant. Sans elles, le fil est en lecture seule. */
  actions?: (currentStatus: string) => ReactNode;
  /** Suivi de la demande (`SubmissionFollow`). */
  follow?: ReactNode;
  /** Auteur, membres et managers de l'équipe, admin (la base vérifie le même droit). */
  canConfirm?: boolean;
  /** Le lecteur a accès au PDF joint. */
  showAttachment?: boolean;
  onClose: () => void;
}) {
  const qc = useQueryClient();
  const history = useQuery({
    queryKey: ["submissions", "history", submission.id],
    queryFn: () => fetchSubmissionHistory(submission.id),
    retry: false,
  });
  const verifications = useQuery({
    queryKey: ["submissions", "verifications", submission.id],
    queryFn: () => fetchSubmissionVerifications(submission.id),
    retry: false,
  });
  const statusSteps = sortSteps(history.data ?? []);
  const status = statusSteps[0]?.new_status ?? submission.status;
  const steps = sortSteps([
    ...statusSteps,
    ...(verifications.data ?? []).map((v) => verificationStep(v, status)),
  ]);
  const last = steps[0];
  const confirm = useMutation({
    mutationFn: () => confirmSubmissionUpToDate(submission.id),
    onSuccess: async () => {
      toast.success("Demande confirmée à jour.");
      await qc.invalidateQueries({ queryKey: ["submissions"] });
    },
    onError: (e) => toast.error((e as Error).message),
  });
  const loaded = !history.isLoading && !verifications.isLoading;
  const failed = history.isError || verifications.isError;
  const updatedAt = last?.changed_at ?? submission.created_at;
  // « Lecture seule » tant que le lecteur n'a aucune action possible ici.
  const confirmable = !!canConfirm && submissionStaleDays(status, updatedAt) != null;
  return (
    <SubmissionThreadView
      content={submission.content}
      team={submission.team}
      steps={steps}
      readOnly={!actions && !confirmable}
      actions={actions?.(status)}
      follow={follow}
      attachment={
        showAttachment ? (
          <AttachmentLink path={submission.attachment_path} name={submission.attachment_name} />
        ) : undefined
      }
      upToDate={
        loaded && !failed ? (
          <SubmissionUpToDate
            status={status}
            updatedAt={updatedAt}
            verifiedBy={last?.kind === "verification" ? last.changed_by_name : undefined}
            pending={confirm.isPending}
            onConfirm={canConfirm ? () => confirm.mutate() : undefined}
          />
        ) : undefined
      }
      loading={!loaded}
      error={failed}
      onClose={onClose}
    />
  );
}
