import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useRef, useState } from "react";
import { toast } from "sonner";
import { BrandHeader } from "@/components/brand-header";
import {
  DS_INPUT,
  DsButton,
  DsEmptyState,
  DsField,
  DsListItem,
  DsSaveStatus,
  DsSection,
} from "@/components/ds";
import { NewsAudienceField } from "@/components/news/NewsAudienceField";
import { useAutosaveDraft } from "@/components/news/use-autosave-draft";
import { NewsMediaEditor } from "@/components/news-media";
import { ConfirmDialog } from "@/components/overview/ConfirmDialog";
import { OverviewHeader } from "@/components/overview/OverviewHeader";
import { ReaderDialog } from "@/components/reader-dialog";
import { GlobalSearch } from "@/components/search/GlobalSearch";
import { validate, newsContentSchema } from "@/lib/manage-schemas";
import {
  audienceError,
  audienceSentence,
  emptyAudience,
  type NewsAudienceValue,
} from "@/lib/news-audience";
import { emptyMedia, type MediaDraft } from "@/lib/news-media";
import {
  BRACKETS_LEFT,
  NEWS_TEMPLATES,
  bracketsLeft,
  type NewsTemplate,
} from "@/lib/news-templates";

export const Route = createFileRoute("/_authenticated/maquettes/us25")({
  head: () => ({
    meta: [{ title: "Happy Place · Maquette des modèles d'actu" }],
  }),
  component: Us25Mockup,
});

// ---------------------------------------------------------------------------
// Données factices (fictif)
// ---------------------------------------------------------------------------

const TEAMS = ["Marketing", "Product"];
const SUBTITLE = "font-label-md text-label-md normal-case tracking-normal text-on-surface-variant";
const TEMPLATE_ICONS: Record<string, string> = {
  arrivee: "person_add",
  mission: "handshake",
  "point-etape": "flag",
  rappel: "campaign",
};

type Draft = { id: string; title: string; body: string; audience: NewsAudienceValue };

const MISSION = NEWS_TEMPLATES[1];
/** Brouillon issu de « Mission gagnée », à moitié complété (fictif). */
const HALF_DONE: Draft = {
  id: "brouillon-mission",
  title: MISSION.title.replace("[client]", "Maison Durand (fictif)"),
  body: MISSION.body.replaceAll("[client]", "Maison Durand (fictif)"),
  audience: { audience: "entreprise", teams: [] },
};
const OWN_TEXT = {
  title: "Nouvel outil de planification (fictif)",
  body: "À partir de lundi, l'équipe passe au nouvel outil de planification (fictif).",
};

type Dialog = { view: "list" } | { view: "preview"; template: NewsTemplate } | null;

type Scenario = {
  value: string;
  label: string;
  note: string;
  title: string;
  body: string;
  editing?: Draft;
  dialog: Dialog;
  replacing?: boolean;
  publishTried?: boolean;
};

const SCENARIOS: Scenario[] = [
  {
    value: "liste",
    label: "Liste des modèles",
    note: "Le rédacteur est vide : « Partir d'un modèle » ouvre les 4 modèles. Choisis-en un pour voir son aperçu.",
    title: "",
    body: "",
    dialog: { view: "list" },
  },
  {
    value: "apercu",
    label: "Aperçu d'un modèle",
    note: "« Utiliser ce modèle » remplit le titre et le texte ; le brouillon s'enregistre 2 s plus tard, avec ses crochets (voir « Mes brouillons »).",
    title: "",
    body: "",
    dialog: { view: "preview", template: NEWS_TEMPLATES[0] },
  },
  {
    value: "remplacer",
    label: "Remplacer un texte existant",
    note: "Le titre et le texte sont déjà remplis : choisir un modèle demande une confirmation. « Annuler » revient à l'aperçu sans rien changer.",
    ...OWN_TEXT,
    dialog: { view: "preview", template: NEWS_TEMPLATES[2] },
    replacing: true,
  },
  {
    value: "refus",
    label: "Publication refusée (crochets)",
    note: "Ce brouillon vient de « Mission gagnée ». « Publier » est refusé tant qu'il reste des crochets. Complète-les puis clique à nouveau sur « Publier ».",
    title: HALF_DONE.title,
    body: HALF_DONE.body,
    editing: HALF_DONE,
    dialog: null,
    publishTried: true,
  },
];

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

type AutosaveValue = { title: string; body: string; audience: NewsAudienceValue };
const EMPTY: AutosaveValue = { title: "", body: "", audience: emptyAudience() };

/** Mêmes règles que la publication de NewsSection, plus les crochets (US25), avant la confirmation. */
function publishErrors(title: string, body: string) {
  const res = validate(newsContentSchema, { title, body, status: "publiée" });
  const errs = res.ok ? {} : res.errors;
  return {
    title: errs.title ?? (bracketsLeft(title).length ? BRACKETS_LEFT : undefined),
    body: errs.body ?? (bracketsLeft(body).length ? BRACKETS_LEFT : undefined),
  };
}

// ---------------------------------------------------------------------------
// Présentation
// ---------------------------------------------------------------------------

function Composer({ scenario }: { scenario: Scenario }) {
  const initialErrors = scenario.publishTried
    ? publishErrors(scenario.title, scenario.body)
    : { title: undefined, body: undefined };
  const [drafts, setDrafts] = useState<Draft[]>(scenario.editing ? [scenario.editing] : []);
  const [editing, setEditing] = useState<Draft | null>(scenario.editing ?? null);
  const [title, setTitle] = useState(scenario.title);
  const [body, setBody] = useState(scenario.body);
  const [audience, setAudience] = useState<NewsAudienceValue>(
    scenario.editing?.audience ?? emptyAudience(),
  );
  const [media, setMedia] = useState<MediaDraft>(emptyMedia);
  const [titleError, setTitleError] = useState(initialErrors.title);
  const [bodyError, setBodyError] = useState(initialErrors.body);
  const [audienceErr, setAudienceErr] = useState<string | undefined>();
  const [dialog, setDialog] = useState<Dialog>(scenario.dialog);
  const [replacing, setReplacing] = useState(!!scenario.replacing);
  const [confirmPublish, setConfirmPublish] = useState(false);
  const titleRef = useRef<HTMLInputElement>(null);
  const bodyRef = useRef<HTMLTextAreaElement>(null);
  const audienceInput = useRef<HTMLInputElement>(null);
  const previewTitle = useRef<HTMLHeadingElement>(null);

  const autosave = useAutosaveDraft<AutosaveValue>({
    value: { title: title.trim(), body, audience },
    isEmpty: (v) => !v.title && !v.body.trim(),
    baseline: scenario.editing
      ? { title: scenario.editing.title, body: scenario.editing.body, audience }
      : EMPTY,
    enabled: true,
    // Comme autosaveDraftNews : crée sans id, met à jour avec un id (fictif).
    save: async (v, id) => {
      await sleep(600);
      const draftId = id ?? `brouillon-${crypto.randomUUID()}`;
      setDrafts((list) =>
        id ? list.map((d) => (d.id === id ? { ...d, ...v } : d)) : [{ id: draftId, ...v }, ...list],
      );
      return draftId;
    },
  });

  useEffect(() => {
    if (scenario.publishTried) titleRef.current?.focus();
  }, [scenario.publishTried]);

  useEffect(() => {
    if (dialog?.view === "preview") previewTitle.current?.focus();
  }, [dialog]);

  function apply(template: NewsTemplate) {
    setTitle(template.title);
    setBody(template.body);
    setTitleError(undefined);
    setBodyError(undefined);
    setReplacing(false);
    setDialog(null);
    // Laisse la fenêtre rendre le focus avant de le placer dans le titre.
    setTimeout(() => titleRef.current?.focus(), 0);
  }

  function chooseTemplate(template: NewsTemplate) {
    if (title.trim() || body.trim()) setReplacing(true);
    else apply(template);
  }

  function publish() {
    const errs = publishErrors(title, body);
    const missing = audienceError(audience);
    setTitleError(errs.title);
    setBodyError(errs.body);
    setAudienceErr(missing);
    if (errs.title) titleRef.current?.focus();
    else if (errs.body) bodyRef.current?.focus();
    else if (missing) audienceInput.current?.focus();
    else setConfirmPublish(true);
  }

  function open(d: Draft) {
    setEditing(d);
    setTitle(d.title);
    setBody(d.body);
    setAudience(d.audience);
    setTitleError(undefined);
    setBodyError(undefined);
    autosave.reset({ title: d.title, body: d.body, audience: d.audience }, d.id);
    titleRef.current?.focus();
  }

  const preview = dialog?.view === "preview" ? dialog.template : null;

  return (
    <DsSection id="actus" title="Actualités du cabinet">
      <DsButton icon="edit" aria-expanded aria-controls="redacteur-actu" className="w-full">
        Rédiger une actualité
      </DsButton>
      <form
        id="redacteur-actu"
        className="space-y-md"
        noValidate
        onSubmit={(e) => {
          e.preventDefault();
          toast.success("Brouillon enregistré (fictif)");
        }}
      >
        <DsButton icon="description" onClick={() => setDialog({ view: "list" })}>
          Partir d'un modèle
        </DsButton>
        <DsField id="actu-titre" label="Titre" error={titleError}>
          <input
            id="actu-titre"
            ref={titleRef}
            type="text"
            className={DS_INPUT}
            placeholder="Saisis un titre…"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
          />
        </DsField>
        <DsField id="actu-contenu" label="Contenu" error={bodyError}>
          <textarea
            id="actu-contenu"
            ref={bodyRef}
            rows={8}
            className={DS_INPUT}
            placeholder="Rédige l'actualité…"
            value={body}
            onChange={(e) => setBody(e.target.value)}
          />
        </DsField>
        <NewsMediaEditor value={media} onChange={setMedia} linkErrs={{}} title={title} />
        <NewsAudienceField
          id="actu-public"
          teams={TEAMS}
          scope="mine"
          value={audience}
          error={audienceErr}
          firstInputRef={audienceInput}
          onChange={(value) => {
            setAudience(value);
            setAudienceErr(undefined);
          }}
        />
        <DsSaveStatus
          state={autosave.status.state}
          at={autosave.status.at}
          onRetry={() => void autosave.flush()}
        />
        <div className="flex flex-wrap items-center justify-end gap-xs">
          <DsButton type="submit">Enregistrer le brouillon</DsButton>
          {editing && (
            <DsButton variant="confirm" onClick={publish}>
              Publier
            </DsButton>
          )}
        </div>
      </form>
      <div className="space-y-xs">
        <h3 className={SUBTITLE}>Mes brouillons</h3>
        {drafts.length === 0 && <DsEmptyState>Aucun brouillon en cours.</DsEmptyState>}
        {drafts.map((d) => (
          <DsListItem
            key={d.id}
            icon="draft"
            title={d.title || <span className="italic">Sans titre</span>}
            meta="Créé aujourd'hui (fictif)"
            onClick={() => open(d)}
          />
        ))}
      </div>

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
                <DsButton variant="confirm" onClick={() => chooseTemplate(preview)}>
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
      <ConfirmDialog
        open={confirmPublish}
        title={`Publier « ${title.trim()} » ?`}
        description={audienceSentence(audience)}
        confirmLabel="Publier"
        onCancel={() => setConfirmPublish(false)}
        onConfirm={() => {
          setConfirmPublish(false);
          toast.success("Actu publiée (fictif)");
          setDrafts((list) => list.filter((d) => d.id !== editing?.id));
          setEditing(null);
          setTitle("");
          setBody("");
          setAudience(emptyAudience());
          autosave.reset(EMPTY);
        }}
      />
    </DsSection>
  );
}

function Us25Mockup() {
  const [scenarioValue, setScenarioValue] = useState(SCENARIOS[0].value);
  const scenario = SCENARIOS.find((s) => s.value === scenarioValue) ?? SCENARIOS[0];

  return (
    <div className="bg-background text-on-surface font-body-md min-h-screen flex flex-col">
      <BrandHeader>
        <OverviewHeader
          isAdmin={false}
          name="Kesha (fictif)"
          role="manager"
          exporting={false}
          onExport={() => toast.info("Non branché dans la maquette (fictif).")}
          search={
            <GlobalSearch
              source={{
                data: { news: [], submissions: [], blockers: [], metrics: [] },
                isError: false,
                isLoading: false,
              }}
            />
          }
        />
      </BrandHeader>
      <main className="flex-grow w-full max-w-interface mx-auto p-sm md:p-md space-y-md">
        <div className="flex flex-wrap items-end gap-sm border border-dashed border-outline-variant p-sm">
          <DsField id="maquette-etat" label="Maquette (fictif)" className="w-full md:w-72">
            <select
              id="maquette-etat"
              className={DS_INPUT}
              value={scenario.value}
              onChange={(e) => setScenarioValue(e.target.value)}
            >
              {SCENARIOS.map((s) => (
                <option key={s.value} value={s.value}>
                  {s.label}
                </option>
              ))}
            </select>
          </DsField>
          <p
            role="status"
            className="min-w-0 flex-1 basis-64 font-body-sm text-body-sm text-on-surface"
          >
            Maquette (fictif) : {scenario.note}
          </p>
        </div>
        <Composer key={scenario.value} scenario={scenario} />
      </main>
    </div>
  );
}
