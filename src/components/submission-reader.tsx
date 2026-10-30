import * as DialogPrimitive from "@radix-ui/react-dialog";
import { Linkify } from "@/components/linkify";
import { AttachmentLink } from "@/components/attachment-link";
import { formatExactDate } from "@/components/expandable-card";
import { DsButton } from "@/components/ds";
import { statusLabel as formatStatus } from "@/components/overview/overview-utils";
import type { Submission } from "@/lib/dashboard";

/** Grande fenêtre de lecture d'une demande (focus piégé, Échap, clic fond). */
export function SubmissionReader({
  submission: s,
  statusLabel,
  onClose,
  onReject,
  onApprove,
  approving,
  statusActions,
}: {
  submission: Submission | null;
  statusLabel?: string;
  onClose: () => void;
  onReject?: () => void;
  onApprove?: () => void;
  approving?: boolean;
  /** Autres changements de statut possibles (le manager peut en changer autant de fois que nécessaire). */
  statusActions?: { label: string; onClick: () => void }[];
}) {
  return (
    <DialogPrimitive.Root open={!!s} onOpenChange={(o) => !o && onClose()}>
      <DialogPrimitive.Portal>
        <DialogPrimitive.Overlay className="fixed inset-0 z-50 bg-black/50" />
        {s && (
          <DialogPrimitive.Content
            className="fixed z-50 inset-0 md:inset-auto md:left-1/2 md:top-1/2 md:-translate-x-1/2 md:-translate-y-1/2 w-full md:w-[min(48rem,calc(100vw-2rem))] h-dvh md:h-auto md:max-h-[85vh] flex flex-col bg-surface-container-lowest border border-outline shadow-lg focus:outline-none"
          >
            <div className="flex items-start justify-between gap-sm border-b border-outline-variant p-md">
              <div className="min-w-0">
                <DialogPrimitive.Title className="font-headline-sm text-headline-sm text-primary wrap-anywhere">
                  {s.author_name}
                </DialogPrimitive.Title>
                <DialogPrimitive.Description className="font-label-md text-label-md normal-case tracking-normal text-on-surface-variant">
                  {s.team} · {formatStatus(statusLabel ?? s.status)} · Créée le {formatExactDate(s.created_at)}
                </DialogPrimitive.Description>
              </div>
              <DialogPrimitive.Close
                aria-label="Fermer"
                className="inline-flex size-11 shrink-0 items-center justify-center text-on-surface-variant hover:text-primary focus:outline-none focus-visible:ring-2 focus-visible:ring-primary"
              >
                <span aria-hidden="true" className="material-symbols-outlined">close</span>
              </DialogPrimitive.Close>
            </div>
            <div className="flex-1 overflow-y-auto p-md space-y-md">
              <p className="font-body-md text-body-md text-on-surface whitespace-pre-line wrap-anywhere">
                <Linkify text={s.content} />
              </p>
              <AttachmentLink path={s.attachment_path} name={s.attachment_name} />
              {s.status === "refusée" && s.rejection_category && (
                <div className="p-sm bg-error-container text-on-error-container text-body-sm wrap-anywhere">
                  <p className="font-bold">Motif : {s.rejection_category}</p>
                  <p className="whitespace-pre-line">Raison : <Linkify text={s.rejection_note ?? ""} /></p>
                </div>
              )}
            </div>
            {(onReject || onApprove || statusActions?.length) && (
              <div className="flex flex-wrap gap-xs border-t border-outline-variant p-md">
                {statusActions?.map((a) => (
                  <DsButton key={a.label} disabled={approving} onClick={a.onClick} className="flex-1">
                    {a.label}
                  </DsButton>
                ))}
                {onReject && (
                  <DsButton onClick={onReject} className="flex-1">
                    Refuser
                  </DsButton>
                )}
                {onApprove && (
                  <DsButton variant="confirm" disabled={approving} onClick={onApprove} className="flex-1">
                    Valider
                  </DsButton>
                )}
              </div>
            )}
          </DialogPrimitive.Content>
        )}
      </DialogPrimitive.Portal>
    </DialogPrimitive.Root>
  );
}
