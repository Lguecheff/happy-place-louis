import { createFileRoute } from "@tanstack/react-router";
import { useRef, useState } from "react";
import { toast } from "sonner";
import { BrandHeader } from "@/components/brand-header";
import { DS_INPUT, DsField } from "@/components/ds";
import type { NewsTemplatePickerInitial } from "@/components/news/NewsTemplatePicker";
import type { AutosaveFn } from "@/components/news/use-autosave-draft";
import {
  NewsSection,
  type AutosaveInput,
  type DraftInput,
} from "@/components/overview/NewsSection";
import { OverviewHeader } from "@/components/overview/OverviewHeader";
import { GlobalSearch } from "@/components/search/GlobalSearch";
import type { News } from "@/lib/dashboard";
import { NEWS_TEMPLATES } from "@/lib/news-templates";

export const Route = createFileRoute("/_authenticated/maquettes/us25")({
  head: () => ({
    meta: [{ title: "Happy Place · Maquette des modèles d'actu" }],
  }),
  component: Us25Mockup,
});

// ---------------------------------------------------------------------------
// Données factices (fictif). Le rédacteur est le vrai NewsSection.
// ---------------------------------------------------------------------------

const KESHA = { author: "Kesha (fictif)", author_email: "kesha@fictif.test" };
const MISSION = NEWS_TEMPLATES[1];
const CLIENT = "Maison Durand (fictif)";

/** Brouillon issu de « Mission gagnée », à moitié complété (fictif). */
const HALF_DONE: News = {
  id: "brouillon-mission",
  title: MISSION.title.replace("[client]", CLIENT),
  body: MISSION.body.replaceAll("[client]", CLIENT),
  ...KESHA,
  status: "brouillon",
  created_at: new Date().toISOString(),
  updated_at: new Date().toISOString(),
  published_at: null,
  links: [],
  audience: "entreprise",
  teams: [],
};

type Scenario = {
  value: string;
  label: string;
  note: string;
  draft?: { title: string; body: string };
  picker?: NewsTemplatePickerInitial;
  news: News[];
};

const SCENARIOS: Scenario[] = [
  {
    value: "liste",
    label: "Liste des modèles",
    note: "Choisis un modèle pour voir son aperçu, puis « Utiliser ce modèle » : le brouillon s'enregistre 2 s plus tard, avec ses crochets.",
    picker: {},
    news: [],
  },
  {
    value: "apercu",
    label: "Aperçu d'un modèle",
    note: "Le modèle remplit le titre et le texte, jamais le public.",
    picker: { templateId: "arrivee" },
    news: [],
  },
  {
    value: "remplacer",
    label: "Remplacer un texte existant",
    note: "Le titre et le texte sont déjà remplis : choisir un modèle demande une confirmation.",
    draft: {
      title: "Nouvel outil de planification (fictif)",
      body: "À partir de lundi, l'équipe passe au nouvel outil de planification (fictif).",
    },
    picker: { templateId: "point-etape", replacing: true },
    news: [],
  },
  {
    value: "refus",
    label: "Publication refusée (crochets)",
    note: "Ouvre le brouillon « Mission gagnée » dans « Mes brouillons », puis clique sur « Publier » : c'est refusé tant qu'il reste des crochets.",
    news: [HALF_DONE],
  },
];

function Us25Mockup() {
  const [scenarioValue, setScenarioValue] = useState(SCENARIOS[0].value);
  const scenario = SCENARIOS.find((s) => s.value === scenarioValue) ?? SCENARIOS[0];
  const [news, setNews] = useState<News[]>(scenario.news);
  const [composerOpen, setComposerOpen] = useState(true);
  const composerTitle = useRef<HTMLInputElement>(null);

  /** Comme saveDraftNews : crée sans id, met à jour avec un id (fictif). */
  function writeDraft(input: AutosaveInput, id: string | undefined, status = "brouillon") {
    const now = new Date().toISOString();
    const fields = { title: input.title, body: input.body, links: input.links, ...input.audience };
    const published = status === "publiée" ? { published_at: now } : {};
    if (id) {
      setNews((list) =>
        list.map((n) =>
          n.id === id ? { ...n, ...fields, ...published, status, updated_at: now } : n,
        ),
      );
      return id;
    }
    const created = `brouillon-${crypto.randomUUID()}`;
    const draft = { ...HALF_DONE, ...fields, id: created, created_at: now, updated_at: now };
    setNews((list) => [draft, ...list]);
    return created;
  }

  const autosave: AutosaveFn<AutosaveInput> = async (input, id) => {
    await new Promise((resolve) => setTimeout(resolve, 600));
    return writeDraft(input, id);
  };

  function saveDraft(input: DraftInput, onSaved: () => void) {
    writeDraft(input, input.id);
    toast.success("Brouillon enregistré (fictif)");
    onSaved();
  }

  function publish(input: DraftInput, onPublished: () => void) {
    writeDraft(input, input.id, "publiée");
    toast.success("Actu publiée (fictif)");
    onPublished();
  }

  function chooseScenario(value: string) {
    const next = SCENARIOS.find((s) => s.value === value) ?? SCENARIOS[0];
    setScenarioValue(next.value);
    setNews(next.news);
    setComposerOpen(true);
  }

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
                data: { news, submissions: [], blockers: [], metrics: [] },
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
              onChange={(e) => chooseScenario(e.target.value)}
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
        <NewsSection
          key={scenario.value}
          canWrite
          email={KESHA.author_email}
          news={{ data: news, isError: false, isLoading: false }}
          audienceTeams={["Marketing", "Product"]}
          audienceScope="mine"
          composerOpen={composerOpen}
          onComposerOpenChange={setComposerOpen}
          titleRef={composerTitle}
          saving={false}
          publishing={false}
          removing={false}
          onSave={saveDraft}
          onPublish={publish}
          onRemove={(n) => setNews((list) => list.filter((x) => x.id !== n.id))}
          onRead={() => {}}
          onAutosave={autosave}
          initialDraft={scenario.draft}
          initialTemplatePicker={scenario.picker}
        />
      </main>
    </div>
  );
}
