import { createFileRoute } from "@tanstack/react-router";
import { useRef, useState } from "react";
import { toast } from "sonner";
import { BrandHeader } from "@/components/brand-header";
import { DS_INPUT, DsChoice, DsField } from "@/components/ds";
import { NewsReader } from "@/components/news-reader";
import type { AutosaveFn } from "@/components/news/use-autosave-draft";
import {
  NewsSection,
  type AutosaveInput,
  type DraftInput,
} from "@/components/overview/NewsSection";
import { OverviewHeader } from "@/components/overview/OverviewHeader";
import { GlobalSearch } from "@/components/search/GlobalSearch";
import type { News } from "@/lib/dashboard";

export const Route = createFileRoute("/_authenticated/maquettes/us17")({
  head: () => ({
    meta: [{ title: "Happy Place · Maquette de l'enregistrement automatique" }],
  }),
  component: Us17Mockup,
});

// ---------------------------------------------------------------------------
// Données factices (fictif)
// ---------------------------------------------------------------------------

const PRODUCT = "Product";
const MARKETING = "Marketing";
const KESHA = { author: "Kesha (fictif)", author_email: "kesha@fictif.test" };
const KARIM = { author: "Karim (fictif)", author_email: "karim@fictif.test" };

const DRAFT_TEXT = {
  title: "Nouvel outil de planification (fictif)",
  body: "À partir de lundi, l'équipe passe au nouvel outil de planification (fictif).",
};

type Scenario = {
  value: string;
  label: string;
  /** Contenu déjà saisi à l'ouverture : l'enregistrement part 2 s plus tard. */
  draft?: { title: string; body: string };
  /** Durée simulée d'un enregistrement. */
  delay: number;
  offline: boolean;
  note: string;
};

const SCENARIOS: Scenario[] = [
  {
    value: "vide",
    label: "Rien saisi",
    delay: 800,
    offline: false,
    note: "Le rédacteur est vide : ferme-le, rien n'est créé. Tape un titre ou un texte, attends 2 s : le brouillon apparaît dans « Mes brouillons ».",
  },
  {
    value: "en-cours",
    label: "Enregistrement…",
    draft: DRAFT_TEXT,
    delay: 15_000,
    offline: false,
    note: "Chaque enregistrement dure 15 s. Tape pendant qu'il tourne : ta dernière version part à la fin, sans second enregistrement en parallèle.",
  },
  {
    value: "enregistre",
    label: "Enregistré à HH:MM",
    draft: DRAFT_TEXT,
    delay: 800,
    offline: false,
    note: "Continue à taper : le même brouillon est mis à jour, le compteur de créations reste à 1. Vide le titre et le texte : rien n'est envoyé.",
  },
  {
    value: "echec",
    label: "Échec avec Réessayer",
    draft: DRAFT_TEXT,
    delay: 800,
    offline: true,
    note: "Le réseau est coupé (fictif) : ton texte reste dans le rédacteur. Rétablis le réseau, puis clique sur « Réessayer ».",
  },
];

const DAY_MS = 86_400_000;
const daysAgo = (days: number) => new Date(Date.now() - days * DAY_MS).toISOString();

function mockNews(id: string, days: number, extra: Partial<News>): News {
  const at = daysAgo(days);
  return {
    id,
    title: "",
    body: "Texte de l'actu (fictif).",
    ...KESHA,
    status: "publiée",
    created_at: at,
    updated_at: at,
    published_at: at,
    links: [],
    audience: "entreprise",
    teams: [],
    ...extra,
  };
}

const NEWS: News[] = [
  mockNews("brouillon-kesha", 2, {
    title: "Point d'étape de l'équipe (fictif)",
    status: "brouillon",
    published_at: null,
    audience: "équipe",
    teams: [PRODUCT],
  }),
  mockNews("publiee-kesha", 4, { title: "Bilan du trimestre (fictif)" }),
  mockNews("publiee-karim", 6, { title: "Calendrier des campagnes (fictif)", ...KARIM }),
];

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

// ---------------------------------------------------------------------------
// Présentation
// ---------------------------------------------------------------------------

function Us17Mockup() {
  const [scenarioValue, setScenarioValue] = useState(SCENARIOS[0].value);
  const [news, setNews] = useState(NEWS);
  const [reading, setReading] = useState<News | null>(null);
  const [composerOpen, setComposerOpen] = useState(true);
  const [offline, setOffline] = useState(SCENARIOS[0].offline);
  const [counts, setCounts] = useState({ created: 0, updated: 0, failed: 0 });
  const composerTitle = useRef<HTMLInputElement>(null);
  const offlineRef = useRef(offline);
  offlineRef.current = offline;
  // Un enregistrement lancé avant un changement d'état de la maquette est ignoré.
  const run = useRef(0);

  const scenario = SCENARIOS.find((s) => s.value === scenarioValue) ?? SCENARIOS[0];

  /** Comme saveDraftNews : crée sans id, met à jour avec un id, et renvoie l'id. */
  function writeDraft(input: AutosaveInput, id: string | undefined) {
    const now = new Date().toISOString();
    const fields = { title: input.title, body: input.body, links: input.links, ...input.audience };
    if (id) {
      setNews((list) => list.map((n) => (n.id === id ? { ...n, ...fields, updated_at: now } : n)));
      setCounts((c) => ({ ...c, updated: c.updated + 1 }));
      return id;
    }
    const created = `brouillon-${crypto.randomUUID()}`;
    const draft = mockNews(created, 0, { ...fields, status: "brouillon", published_at: null });
    setNews((list) => [draft, ...list]);
    setCounts((c) => ({ ...c, created: c.created + 1 }));
    return created;
  }

  const autosave: AutosaveFn<AutosaveInput> = async (input, id) => {
    const started = run.current;
    await sleep(scenario.delay);
    if (started !== run.current) return id ?? "";
    if (offlineRef.current) {
      setCounts((c) => ({ ...c, failed: c.failed + 1 }));
      throw new Error("Réseau coupé (fictif)");
    }
    return writeDraft(input, id);
  };

  function saveDraft(input: DraftInput, onSaved: () => void) {
    if (offlineRef.current) {
      toast.error("Réseau coupé (fictif) : le brouillon n'est pas enregistré.");
      return;
    }
    writeDraft(input, input.id);
    toast.success("Brouillon enregistré (fictif)");
    onSaved();
  }

  function publish(input: DraftInput & { id: string }, onPublished: () => void) {
    writeDraft(input, input.id);
    const now = new Date().toISOString();
    setNews((list) =>
      list.map((n) => (n.id === input.id ? { ...n, status: "publiée", published_at: now } : n)),
    );
    toast.success("Actualité publiée (fictif)");
    onPublished();
  }

  function chooseScenario(value: string) {
    const next = SCENARIOS.find((s) => s.value === value) ?? SCENARIOS[0];
    run.current += 1;
    setScenarioValue(next.value);
    setOffline(next.offline);
    setNews(NEWS);
    setCounts({ created: 0, updated: 0, failed: 0 });
    setReading(null);
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
          <div className="w-full md:w-56">
            <DsChoice
              type="checkbox"
              label="Réseau coupé (fictif)"
              checked={offline}
              onChange={(e) => setOffline(e.target.checked)}
            />
          </div>
          <div className="min-w-0 flex-1 basis-64 space-y-1 font-body-sm text-body-sm text-on-surface-variant">
            <p role="status" className="text-on-surface">
              Maquette (fictif) : {scenario.note}
            </p>
            <p>
              Brouillons créés : {counts.created} · Mises à jour : {counts.updated} · Échecs :{" "}
              {counts.failed} (fictif). L'image ne part qu'avec « Enregistrer le brouillon ».
            </p>
          </div>
        </div>
        <NewsSection
          key={scenario.value}
          canWrite
          email={KESHA.author_email}
          news={{ data: news, isError: false, isLoading: false }}
          audienceTeams={[MARKETING, PRODUCT]}
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
          onRead={setReading}
          onAutosave={autosave}
          initialDraft={scenario.draft}
        />
      </main>
      <NewsReader news={reading} onClose={() => setReading(null)} />
    </div>
  );
}
