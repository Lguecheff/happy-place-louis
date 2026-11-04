import { useEffect, useRef, useState } from "react";
import { toast } from "sonner";
import { DsButton, DsIcon, DsPopover, toastUndo } from "@/components/ds";
import { ReaderDialog } from "@/components/reader-dialog";
import {
  AI_IMPROVE_ACTIONS,
  AI_IMPROVE_MESSAGES,
  AI_MESSAGES,
  AI_TIMEOUT_MS,
  AI_UNDO_MS,
  type AiDraft,
  type AiImprove,
  type AiImproveAction,
} from "@/lib/news-ai";

type Phase = "loading" | "compare" | "error" | "limit";

/** État de départ (maquettes). « replaced » rejoue le remplacement et son toast d'annulation. */
export type NewsAiImproverInitial =
  | { phase: "menu" }
  | { phase: "compare"; action: AiImproveAction; before: AiDraft; after: AiDraft }
  | { phase: "error"; action: AiImproveAction; before: AiDraft }
  | { phase: "replaced"; before: AiDraft; after: AiDraft };

const BOX = "space-y-xs border border-outline-variant p-sm";
const LABEL = "font-label-md text-label-md text-on-surface-variant";

function Side({ label, title, body, muted }: AiDraft & { label: string; muted?: boolean }) {
  return (
    <div className={`${BOX} ${muted ? "bg-surface-container" : "bg-surface-container-lowest"}`}>
      <p className={LABEL}>{label}</p>
      {title && (
        <p className="font-body-md text-body-md font-bold text-primary wrap-anywhere">{title}</p>
      )}
      <p className="font-body-sm text-body-sm whitespace-pre-line text-on-surface wrap-anywhere">
        {body}
      </p>
    </div>
  );
}

/**
 * « Améliorer avec l'IA » (US28) : menu de quatre actions sur le texte écrit par l'auteur,
 * puis avant / après avec « Remplacer » et « Annuler ». Après un remplacement, le toast
 * d'annulation garde l'ancien texte 10 secondes. Le formulaire n'est jamais touché sans
 * « Remplacer », ni en cas d'échec.
 */
export function NewsAiImprover({
  title,
  body,
  onReplace,
  improve,
  disabled,
  initial,
}: {
  title: string;
  body: string;
  /** Écrit le titre et le texte dans le formulaire (remplacement ou annulation). */
  onReplace: (draft: AiDraft) => void;
  improve: AiImprove;
  disabled?: boolean;
  initial?: NewsAiImproverInitial;
}) {
  const startCompare = initial?.phase === "compare" || initial?.phase === "error";
  const [menuOpen, setMenuOpen] = useState(initial?.phase === "menu");
  const [phase, setPhase] = useState<Phase | null>(
    initial?.phase === "compare" ? "compare" : initial?.phase === "error" ? "error" : null,
  );
  const [action, setAction] = useState<AiImproveAction>(startCompare ? initial.action : "corriger");
  const [before, setBefore] = useState<AiDraft>(startCompare ? initial.before : { title, body });
  const [after, setAfter] = useState<AiDraft | null>(
    initial?.phase === "compare" ? initial.after : null,
  );
  const abort = useRef<AbortController | null>(null);
  const afterTitle = useRef<HTMLHeadingElement>(null);
  const toastId = useRef<string | number | undefined>(undefined);
  const empty = !body.trim();
  const meta = AI_IMPROVE_ACTIONS.find((a) => a.value === action) ?? AI_IMPROVE_ACTIONS[0];
  const loading = phase === "loading";

  useEffect(() => {
    if (phase === "compare") afterTitle.current?.focus();
  }, [phase]);

  // Maquette « Après remplacement » : le formulaire reçoit le texte de l'IA et le toast s'affiche.
  const replayed = useRef(false);
  useEffect(() => {
    if (initial?.phase !== "replaced" || replayed.current) return;
    replayed.current = true;
    const timer = setTimeout(() => replace(initial.before, initial.after), 50);
    return () => clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(
    () => () => {
      abort.current?.abort("cancel");
      // Le rédacteur n'est plus là : l'annulation n'aurait plus rien à rétablir.
      if (toastId.current !== undefined) toast.dismiss(toastId.current);
    },
    [],
  );

  async function run(next: AiImproveAction, source: AiDraft) {
    setMenuOpen(false);
    setAction(next);
    setBefore(source);
    setAfter(null);
    abort.current?.abort("cancel");
    const controller = new AbortController();
    abort.current = controller;
    const timer = setTimeout(() => controller.abort(), AI_TIMEOUT_MS);
    setPhase("loading");
    try {
      const withTitle = AI_IMPROVE_ACTIONS.find((a) => a.value === next)?.withTitle;
      const result = await improve(
        { action: next, title: withTitle ? source.title : "", body: source.body },
        controller.signal,
      );
      if (controller.signal.aborted) throw new Error("abandon");
      if (result.ok) {
        setAfter({
          title: withTitle ? (result.title ?? source.title) : source.title,
          body: result.body,
        });
        setPhase("compare");
      } else setPhase(result.reason === "limit" ? "limit" : "error");
    } catch {
      // Annulation par l'utilisateur : la fenêtre se ferme, sans message.
      if (abort.current === controller) {
        if (controller.signal.reason === "cancel") setPhase(null);
        else setPhase("error");
      }
    } finally {
      clearTimeout(timer);
      if (abort.current === controller) abort.current = null;
    }
  }

  function close() {
    abort.current?.abort("cancel");
    setPhase(null);
    setAfter(null);
  }

  /** Remplace, puis garde l'ancien texte 10 secondes dans le toast d'annulation. */
  function replace(previous: AiDraft, next: AiDraft) {
    close();
    if (toastId.current !== undefined) toast.dismiss(toastId.current);
    // Après la fermeture, la fenêtre rend le focus au bouton : le formulaire le reprend ensuite.
    setTimeout(() => {
      onReplace(next);
      toastId.current = toastUndo(AI_IMPROVE_MESSAGES.replaced, () => onReplace(previous), {
        duration: AI_UNDO_MS,
      });
    }, 0);
  }

  const unchanged = after && after.title === before.title && after.body === before.body;

  return (
    <div className="space-y-xs">
      <DsPopover
        open={menuOpen}
        onOpenChange={setMenuOpen}
        title="Améliorer avec l'IA"
        trigger={
          <DsButton icon="auto_awesome" disabled={disabled || empty} aria-haspopup="dialog">
            Améliorer avec l'IA
          </DsButton>
        }
      >
        <div className="space-y-sm">
          <ul className="space-y-xs">
            {AI_IMPROVE_ACTIONS.map((a) => (
              <li key={a.value}>
                <DsButton
                  icon={a.icon}
                  className="w-full justify-start"
                  onClick={() => void run(a.value, { title, body })}
                >
                  {a.label}
                </DsButton>
              </li>
            ))}
          </ul>
          <p className="flex items-start gap-xs font-body-sm text-body-sm text-on-surface-variant">
            <DsIcon name="info" />
            {AI_IMPROVE_MESSAGES.privacy}
          </p>
        </div>
      </DsPopover>
      {empty && (
        <p className="font-label-md text-label-md text-on-surface-variant">
          Écris d'abord ton texte pour l'améliorer avec l'IA.
        </p>
      )}

      {phase && (
        <ReaderDialog
          title={meta.label}
          subtitle={
            meta.withTitle
              ? "Sur le titre et le texte. Rien n'est remplacé sans ton accord."
              : "Sur le texte seulement. Rien n'est remplacé sans ton accord."
          }
          onClose={close}
        >
          <div role="status" aria-live="polite" className="font-body-sm text-body-sm">
            {loading && (
              <p className="flex items-center gap-xs text-on-surface">
                <DsIcon name="progress_activity" className="animate-spin" />
                {AI_IMPROVE_MESSAGES.loading}
              </p>
            )}
          </div>
          {phase === "error" && (
            <p role="alert" className="font-body-sm text-body-sm text-error">
              {AI_MESSAGES.error}
            </p>
          )}
          {phase === "limit" && (
            <p role="alert" className={`${BOX} bg-surface-container font-body-sm text-body-sm`}>
              {AI_MESSAGES.limit}
            </p>
          )}

          {phase === "compare" && after && (
            <div className="space-y-md">
              <h3
                ref={afterTitle}
                tabIndex={-1}
                className="font-body-md text-body-md font-bold text-primary focus:outline-none"
              >
                Avant / après
              </h3>
              <p className="flex items-start gap-xs font-body-sm text-body-sm text-on-surface">
                <DsIcon name="info" />
                {unchanged ? AI_IMPROVE_MESSAGES.unchanged : AI_MESSAGES.review}
              </p>
              <div className="grid gap-sm md:grid-cols-2">
                <Side
                  label="Avant"
                  title={meta.withTitle ? before.title : ""}
                  body={before.body}
                  muted
                />
                <Side
                  label="Après, proposé par l'IA"
                  title={meta.withTitle ? after.title : ""}
                  body={after.body}
                />
              </div>
            </div>
          )}

          <div className="flex flex-wrap items-center justify-end gap-xs">
            <DsButton variant="link" className="mr-auto" onClick={close}>
              Annuler
            </DsButton>
            {phase === "error" && (
              <DsButton icon="refresh" onClick={() => void run(action, before)}>
                Réessayer
              </DsButton>
            )}
            {phase === "compare" && after && !unchanged && (
              <DsButton variant="confirm" onClick={() => replace(before, after)}>
                Remplacer
              </DsButton>
            )}
          </div>
        </ReaderDialog>
      )}
    </div>
  );
}
