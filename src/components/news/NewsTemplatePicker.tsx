import { useEffect, useRef, useState } from "react";
import { DsButton, DsListItem } from "@/components/ds";
import { ConfirmDialog } from "@/components/overview/ConfirmDialog";
import { ReaderDialog } from "@/components/reader-dialog";
import { NEWS_TEMPLATES, type NewsTemplate } from "@/lib/news-templates";

const TEMPLATE_ICONS: Record<string, string> = {
  arrivee: "person_add",
  mission: "handshake",
  "point-etape": "flag",
  rappel: "campaign",
};

type View = { view: "list" } | { view: "preview"; template: NewsTemplate } | null;

/** État de départ de la fenêtre (maquettes). */
export type NewsTemplatePickerInitial = { templateId?: string; replacing?: boolean };

/**
 * « Partir d'un modèle » (US25) : bouton, fenêtre des modèles avec aperçu, et
 * confirmation si le titre ou le texte est déjà rempli. Le modèle ne touche pas au public.
 */
export function NewsTemplatePicker({
  hasText,
  onApply,
  disabled,
  initial,
}: {
  /** Le titre ou le texte est déjà rempli : choisir un modèle demande une confirmation. */
  hasText: boolean;
  onApply: (template: NewsTemplate) => void;
  disabled?: boolean;
  initial?: NewsTemplatePickerInitial;
}) {
  const initialTemplate = NEWS_TEMPLATES.find((t) => t.id === initial?.templateId);
  const [dialog, setDialog] = useState<View>(
    initial
      ? initialTemplate
        ? { view: "preview", template: initialTemplate }
        : { view: "list" }
      : null,
  );
  const [replacing, setReplacing] = useState(!!initial?.replacing && !!initialTemplate);
  const previewTitle = useRef<HTMLHeadingElement>(null);
  const preview = dialog?.view === "preview" ? dialog.template : null;

  useEffect(() => {
    if (preview) previewTitle.current?.focus();
  }, [preview]);

  function apply(template: NewsTemplate) {
    setReplacing(false);
    setDialog(null);
    // Après la fermeture, la fenêtre rend le focus au bouton : le formulaire le reprend ensuite.
    setTimeout(() => onApply(template), 0);
  }

  return (
    <>
      <DsButton
        icon="description"
        aria-haspopup="dialog"
        disabled={disabled}
        onClick={() => setDialog({ view: "list" })}
      >
        Partir d'un modèle
      </DsButton>
      {dialog && (
        <ReaderDialog
          title="Partir d'un modèle"
          subtitle="Le modèle remplit le titre et le texte. Tu choisis toujours le public."
          onClose={() => setDialog(null)}
        >
          {preview ? (
            <div className="space-y-md">
              <h3
                ref={previewTitle}
                tabIndex={-1}
                className="font-body-md text-body-md font-bold text-primary focus:outline-none"
              >
                Aperçu : {preview.name}
              </h3>
              <div className="space-y-xs border border-outline-variant bg-surface-container p-sm">
                <p className="font-body-md text-body-md font-bold text-primary wrap-anywhere">
                  {preview.title}
                </p>
                <p className="font-body-sm text-body-sm whitespace-pre-line text-on-surface wrap-anywhere">
                  {preview.body}
                </p>
              </div>
              <p className="font-body-sm text-body-sm text-on-surface-variant">
                Complète les éléments entre crochets, comme [prénom], avant de publier.
              </p>
              <div className="flex flex-wrap items-center justify-end gap-xs">
                <DsButton
                  variant="link"
                  icon="arrow_back"
                  className="mr-auto"
                  onClick={() => setDialog({ view: "list" })}
                >
                  Revenir aux modèles
                </DsButton>
                <DsButton
                  variant="confirm"
                  onClick={() => (hasText ? setReplacing(true) : apply(preview))}
                >
                  Utiliser ce modèle
                </DsButton>
              </div>
            </div>
          ) : (
            <div className="space-y-xs">
              {NEWS_TEMPLATES.map((t) => (
                <DsListItem
                  key={t.id}
                  icon={TEMPLATE_ICONS[t.id]}
                  title={t.name}
                  meta={t.title}
                  onClick={() => setDialog({ view: "preview", template: t })}
                />
              ))}
            </div>
          )}
        </ReaderDialog>
      )}
      <ConfirmDialog
        open={replacing && !!preview}
        title="Remplacer ton texte par le modèle ?"
        description={`Ton titre et ton texte actuels seront remplacés par le modèle « ${preview?.name ?? ""} ». Le public, l'image et les liens ne changent pas.`}
        confirmLabel="Remplacer"
        onCancel={() => setReplacing(false)}
        onConfirm={() => preview && apply(preview)}
      />
    </>
  );
}
