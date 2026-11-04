import { useEffect, useRef, useState } from "react";
import { DS_INPUT, DsButton, DsChoice, DsChoiceGroup, DsField, DsIcon } from "@/components/ds";
import { ConfirmDialog } from "@/components/overview/ConfirmDialog";
import { ReaderDialog } from "@/components/reader-dialog";
import {
  AI_MESSAGES,
  AI_PROMPT_MAX,
  AI_TIMEOUT_MS,
  AI_TONES,
  aiPromptError,
  type AiDraft,
  type AiGenerate,
  type AiTone,
} from "@/lib/news-ai";

type Phase = "prompt" | "loading" | "preview" | "error" | "limit";

/** État de départ de la fenêtre (maquettes). */
export type NewsAiWriterInitial = {
  phase?: Phase;
  prompt?: string;
  tone?: AiTone;
  draft?: AiDraft;
  replacing?: boolean;
};

const BOX = "space-y-xs border border-outline-variant bg-surface-container p-sm";

/**
 * « Rédiger avec l'IA » (US27) : bouton, fenêtre avec la consigne et le ton, aperçu
 * du texte proposé, et confirmation si le titre ou le texte est déjà rempli.
 * Rien n'est écrit dans le formulaire sans « Utiliser ce texte ». La consigne reste
 * gardée à la fermeture, et le formulaire n'est jamais touché en cas d'échec.
 */
export function NewsAiWriter({
  hasText,
  onApply,
  generate,
  disabled,
  initial,
}: {
  /** Le titre ou le texte est déjà rempli : utiliser le texte demande une confirmation. */
  hasText: boolean;
  onApply: (draft: AiDraft) => void;
  generate: AiGenerate;
  disabled?: boolean;
  initial?: NewsAiWriterInitial;
}) {
  const [open, setOpen] = useState(!!initial);
  const [phase, setPhase] = useState<Phase>(initial?.phase ?? "prompt");
  const [prompt, setPrompt] = useState(initial?.prompt ?? "");
  const [tone, setTone] = useState<AiTone>(initial?.tone ?? "informatif");
  const [draft, setDraft] = useState<AiDraft | null>(initial?.draft ?? null);
  const [promptError, setPromptError] = useState<string | undefined>();
  const [replacing, setReplacing] = useState(!!initial?.replacing && !!initial?.draft);
  const abort = useRef<AbortController | null>(null);
  const promptRef = useRef<HTMLTextAreaElement>(null);
  const previewTitle = useRef<HTMLHeadingElement>(null);
  const loading = phase === "loading";

  useEffect(() => {
    if (phase === "preview") previewTitle.current?.focus();
  }, [phase]);

  // Maquette « Chargement » : la génération démarre à l'ouverture.
  useEffect(() => {
    if (initial?.phase === "loading") void run();
    return () => abort.current?.abort();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function run() {
    const err = aiPromptError(prompt);
    setPromptError(err);
    if (err) {
      promptRef.current?.focus();
      return;
    }
    abort.current?.abort();
    const controller = new AbortController();
    abort.current = controller;
    const timer = setTimeout(() => controller.abort(), AI_TIMEOUT_MS);
    setPhase("loading");
    try {
      const result = await generate({ prompt: prompt.trim(), tone }, controller.signal);
      if (controller.signal.aborted) throw new Error("abandon");
      if (result.ok) {
        setDraft({ title: result.title, body: result.body });
        setPhase("preview");
      } else setPhase(result.reason === "limit" ? "limit" : "error");
    } catch {
      // Annulation par l'utilisateur : on revient à la consigne, sans message.
      if (abort.current === controller)
        setPhase(controller.signal.reason === "cancel" ? "prompt" : "error");
    } finally {
      clearTimeout(timer);
      if (abort.current === controller) abort.current = null;
    }
  }

  function cancelLoading() {
    abort.current?.abort("cancel");
  }

  function close() {
    abort.current?.abort("cancel");
    setOpen(false);
    // L'aperçu non utilisé est abandonné ; la consigne et le ton restent.
    if (phase !== "limit") setPhase("prompt");
    setDraft(null);
  }

  function apply() {
    if (!draft) return;
    const chosen = draft;
    setReplacing(false);
    close();
    // Après la fermeture, la fenêtre rend le focus au bouton : le formulaire le reprend ensuite.
    setTimeout(() => onApply(chosen), 0);
  }

  return (
    <>
      <DsButton
        icon="auto_awesome"
        aria-haspopup="dialog"
        disabled={disabled}
        onClick={() => setOpen(true)}
      >
        Rédiger avec l'IA
      </DsButton>
      {open && (
        <ReaderDialog
          title="Rédiger avec l'IA"
          subtitle="L'IA propose un titre et un texte. Rien n'est enregistré sans ton accord."
          onClose={close}
        >
          <form
            className="space-y-md"
            noValidate
            aria-busy={loading}
            onSubmit={(e) => {
              e.preventDefault();
              if (!loading && phase !== "limit") void run();
            }}
          >
            <DsField id="ia-consigne" label="De quoi veux-tu parler ?" error={promptError}>
              <textarea
                id="ia-consigne"
                ref={promptRef}
                rows={3}
                maxLength={AI_PROMPT_MAX}
                readOnly={loading}
                aria-describedby="ia-consigne-aide"
                aria-invalid={!!promptError || undefined}
                className={DS_INPUT}
                placeholder="Par exemple : on lance un afterwork chaque premier jeudi du mois."
                value={prompt}
                onChange={(e) => {
                  setPrompt(e.target.value);
                  if (promptError) setPromptError(aiPromptError(e.target.value));
                }}
              />
              <p
                id="ia-consigne-aide"
                className="flex flex-wrap justify-between gap-xs font-label-md text-label-md text-on-surface-variant"
              >
                <span>{AI_MESSAGES.privacy}</span>
                <span>
                  {prompt.length} caractères sur {AI_PROMPT_MAX}
                </span>
              </p>
            </DsField>
            <DsChoiceGroup legend="Ton">
              <div className="grid gap-xs sm:grid-cols-3">
                {AI_TONES.map((t) => (
                  <DsChoice
                    key={t.value}
                    name="ia-ton"
                    label={t.label}
                    checked={tone === t.value}
                    disabled={loading}
                    onChange={() => setTone(t.value)}
                  />
                ))}
              </div>
            </DsChoiceGroup>

            <div role="status" aria-live="polite" className="font-body-sm text-body-sm">
              {loading && (
                <p className="flex items-center gap-xs text-on-surface">
                  <DsIcon name="progress_activity" className="animate-spin" />
                  {AI_MESSAGES.loading}
                </p>
              )}
            </div>
            {phase === "error" && (
              <p role="alert" className="font-body-sm text-body-sm text-error">
                {AI_MESSAGES.error}
              </p>
            )}
            {phase === "limit" && (
              <p role="alert" className={`${BOX} font-body-sm text-body-sm text-on-surface`}>
                {AI_MESSAGES.limit}
              </p>
            )}

            {phase !== "preview" && (
              <div className="flex flex-wrap items-center justify-end gap-xs">
                {loading && (
                  <DsButton variant="link" onClick={cancelLoading}>
                    Annuler
                  </DsButton>
                )}
                {/* Pendant le chargement, le bouton garde le focus : aria-disabled, pas disabled. */}
                <DsButton
                  type="submit"
                  icon="auto_awesome"
                  disabled={phase === "limit"}
                  aria-disabled={loading || undefined}
                >
                  {phase === "error" ? "Réessayer" : "Proposer un texte"}
                </DsButton>
              </div>
            )}
          </form>

          {phase === "preview" && draft && (
            <div className="space-y-md">
              <h3
                ref={previewTitle}
                tabIndex={-1}
                className="font-body-md text-body-md font-bold text-primary focus:outline-none"
              >
                Texte proposé
              </h3>
              <p className="flex items-start gap-xs font-body-sm text-body-sm text-on-surface">
                <DsIcon name="info" />
                {AI_MESSAGES.review}
              </p>
              <div className={BOX}>
                <p className="font-body-md text-body-md font-bold text-primary wrap-anywhere">
                  {draft.title}
                </p>
                <p className="font-body-sm text-body-sm whitespace-pre-line text-on-surface wrap-anywhere">
                  {draft.body}
                </p>
              </div>
              <div className="flex flex-wrap items-center justify-end gap-xs">
                <DsButton variant="link" className="mr-auto" onClick={close}>
                  Annuler
                </DsButton>
                <DsButton icon="refresh" onClick={() => void run()}>
                  Régénérer
                </DsButton>
                <DsButton
                  variant="confirm"
                  onClick={() => (hasText ? setReplacing(true) : apply())}
                >
                  Utiliser ce texte
                </DsButton>
              </div>
            </div>
          )}
        </ReaderDialog>
      )}
      <ConfirmDialog
        open={replacing && !!draft}
        title="Remplacer ton texte par celui de l'IA ?"
        description="Ton titre et ton texte actuels seront remplacés par le texte proposé. Le public, l'image et les liens ne changent pas."
        confirmLabel="Remplacer"
        onCancel={() => setReplacing(false)}
        onConfirm={apply}
      />
    </>
  );
}
