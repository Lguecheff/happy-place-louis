import { useEffect, useRef, useState } from "react";
import { DsBadge, DsButton, DsIcon, DsSection } from "@/components/ds";
import {
  DIGEST_COOLDOWN_MS,
  digestDateLabel,
  people,
  type DigestSendResult,
  type LastDigest,
} from "@/lib/weekly-digest";

export type DigestStep =
  | { kind: "idle" }
  | { kind: "counting" }
  | { kind: "confirm"; count: number }
  | { kind: "sending"; count: number }
  | { kind: "done"; result: DigestSendResult }
  | { kind: "error"; message: string };

type Props = {
  /** « lundi 9 novembre à 08:00 ». */
  nextLabel: string;
  last: LastDigest | null;
  /** Nombre de destinataires, sans construire le résumé. */
  loadCount: () => Promise<number>;
  send: () => Promise<DigestSendResult>;
  /** Maquette seulement : état de départ. */
  initialStep?: DigestStep;
};

const SEND_ERROR = "Le résumé n'a pas pu être envoyé. Réessaie dans quelques minutes.";

function doneMessage({ recipients, transmitted }: DigestSendResult) {
  if (recipients === 0) return "Résumé enregistré, mais personne ne l'a reçu.";
  if (!transmitted)
    return `Résumé prêt pour ${people(recipients)}, mais pas encore transmis : l'adresse du webhook manque.`;
  return `Résumé envoyé à ${people(recipients)}.`;
}

export function WeeklyDigestCard({ nextLabel, last, loadCount, send, initialStep }: Props) {
  const [step, setStep] = useState<DigestStep>(initialStep ?? { kind: "idle" });
  const [coolingDown, setCoolingDown] = useState(initialStep?.kind === "done");
  const questionRef = useRef<HTMLParagraphElement>(null);
  const resultRef = useRef<HTMLDivElement>(null);
  // DsButton ne transmet pas de ref : on retrouve le bouton dans sa zone.
  const openRef = useRef<HTMLDivElement>(null);
  const focusOpen = () =>
    requestAnimationFrame(() => openRef.current?.querySelector("button")?.focus());

  useEffect(() => {
    if (!coolingDown) return;
    const timer = setTimeout(() => setCoolingDown(false), DIGEST_COOLDOWN_MS);
    return () => clearTimeout(timer);
  }, [coolingDown]);

  useEffect(() => {
    if (step.kind === "confirm") questionRef.current?.focus();
  }, [step.kind]);

  async function ask() {
    setStep({ kind: "counting" });
    try {
      setStep({ kind: "confirm", count: await loadCount() });
    } catch {
      setStep({ kind: "error", message: SEND_ERROR });
    }
  }

  function cancel() {
    setStep({ kind: "idle" });
    focusOpen();
  }

  async function confirm(count: number) {
    setStep({ kind: "sending", count });
    try {
      const result = await send();
      setStep({ kind: "done", result });
      setCoolingDown(true);
    } catch (e) {
      setStep({ kind: "error", message: e instanceof Error && e.message ? e.message : SEND_ERROR });
    }
    // Le bouton est désactivé une minute après un envoi : le focus va sur le message.
    requestAnimationFrame(() => resultRef.current?.focus());
  }

  const confirming = step.kind === "confirm" || step.kind === "sending";

  return (
    <DsSection id="resume-hebdo" title="Résumé hebdomadaire">
      <div className="space-y-sm">
        <p className="flex items-start gap-xs font-body-md text-body-md text-on-surface">
          <DsIcon name="schedule" className="mt-0.5 text-on-surface-variant" />
          <span>Prochain envoi automatique : {nextLabel}</span>
        </p>
        <div className="space-y-xs">
          <h3 className="font-label-md text-label-md text-on-surface-variant">Dernier envoi</h3>
          {last ? (
            <div className="flex flex-wrap items-center gap-xs font-body-sm text-body-sm text-on-surface">
              <span>
                Le {digestDateLabel(last.created_at)} ·{" "}
                {last.mode === "manuel" ? "Manuel" : "Planifié"}
                {last.sent_by_name ? `, par ${last.sent_by_name}` : ""} ·{" "}
                {people(last.recipients_count)}
              </span>
              {last.status === "transmis" ? (
                <DsBadge variant="status" icon="check">
                  Transmis
                </DsBadge>
              ) : (
                <DsBadge variant="watch" icon="hourglass_empty">
                  En attente
                </DsBadge>
              )}
            </div>
          ) : (
            <p className="font-body-sm text-body-sm text-on-surface-variant">
              Aucun résumé envoyé pour l'instant.
            </p>
          )}
        </div>
      </div>

      {confirming ? (
        <div className="space-y-sm border border-outline-variant bg-surface-container p-sm">
          <p
            ref={questionRef}
            tabIndex={-1}
            className="font-body-md text-body-md text-on-surface outline-none"
          >
            {step.count > 0
              ? `Envoyer le résumé des 7 derniers jours à ${people(step.count)} ?`
              : "Personne ne recevra le résumé : aucun collaborateur ni manager n'a d'adresse de réception avec le résumé coché. L'envoi sera seulement enregistré."}
          </p>
          <div className="flex flex-wrap gap-xs">
            <DsButton
              variant="confirm"
              icon="send"
              pending={step.kind === "sending"}
              onClick={() => confirm(step.count)}
            >
              {step.count > 0 ? "Envoyer" : "Enregistrer l'envoi"}
            </DsButton>
            <DsButton disabled={step.kind === "sending"} onClick={cancel}>
              Annuler
            </DsButton>
          </div>
        </div>
      ) : (
        <div ref={openRef} className="flex flex-wrap items-center gap-sm">
          <DsButton
            icon="send"
            pending={step.kind === "counting"}
            disabled={coolingDown}
            onClick={ask}
          >
            Envoyer le résumé maintenant
          </DsButton>
          {coolingDown && (
            <span className="font-body-sm text-body-sm text-on-surface-variant">
              Tu pourras le renvoyer dans une minute.
            </span>
          )}
        </div>
      )}

      {/* Hors message, sr-only garde les zones annoncées sans ajouter d'espace dans la carte. */}
      <div
        ref={resultRef}
        tabIndex={-1}
        className={
          step.kind === "sending" || step.kind === "done" || step.kind === "error"
            ? "outline-none"
            : "sr-only"
        }
      >
        <div role="status" aria-live="polite" className="empty:hidden">
          {step.kind === "sending" && (
            <p className="font-body-sm text-body-sm text-on-surface-variant">Envoi en cours…</p>
          )}
          {step.kind === "done" && (
            <p
              className={
                step.result.transmitted && step.result.recipients > 0
                  ? "flex items-start gap-xs font-body-sm text-body-sm text-success"
                  : "flex items-start gap-xs font-body-sm text-body-sm text-on-surface"
              }
            >
              <DsIcon
                name={
                  step.result.transmitted && step.result.recipients > 0 ? "check_circle" : "info"
                }
                className="mt-0.5"
              />
              <span>{doneMessage(step.result)}</span>
            </p>
          )}
        </div>
        <div role="alert" className="empty:hidden">
          {step.kind === "error" && (
            <p className="flex items-start gap-xs font-body-sm text-body-sm text-error">
              <DsIcon name="error" className="mt-0.5" />
              <span>{step.message}</span>
            </p>
          )}
        </div>
      </div>
    </DsSection>
  );
}
