import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useMemo, useRef, useState } from "react";
import { toast } from "sonner";
import { BrandHeader } from "@/components/brand-header";
import { DS_INPUT, DsButton, DsField, toastUndo } from "@/components/ds";
import { NewsIdeas } from "@/components/news/NewsIdeas";
import {
  NewsSection,
  type DraftInput,
  type NewsSectionHandle,
} from "@/components/overview/NewsSection";
import { OverviewHeader } from "@/components/overview/OverviewHeader";
import { GlobalSearch } from "@/components/search/GlobalSearch";
import type { Blocker, Metric, News } from "@/lib/dashboard";
import { ideaDraft, pickNewsIdeas, type NewsIdea, type ValidatedRequest } from "@/lib/news-ideas";

export const Route = createFileRoute("/_authenticated/maquettes/us26")({
  head: () => ({
    meta: [{ title: "Happy Place · Maquette des idées de sujets" }],
  }),
  component: Us26Mockup,
});

// ---------------------------------------------------------------------------
// Données factices (fictif). Le calcul des idées est le vrai (src/lib/news-ideas.ts).
// ---------------------------------------------------------------------------

const KESHA = {
  name: "Kesha (fictif)",
  email: "kesha@fictif.test",
  teams: ["Marketing", "Product"],
};
const DAY = 24 * 60 * 60 * 1000;
const daysAgo = (n: number) => new Date(Date.now() - n * DAY).toISOString();

const REQUESTS: ValidatedRequest[] = [
  {
    id: "d1",
    team: "Product",
    content:
      "Mettre en place un créneau fixe le jeudi après-midi pour les démos produit internes, ouvert à toutes les équipes, avec un ordre du jour partagé la veille (fictif).",
    validated_at: daysAgo(2),
  },
  {
    id: "d2",
    team: "Marketing",
    content: "Ajouter un modèle de brief commun pour les campagnes de recrutement (fictif).",
    validated_at: daysAgo(9),
  },
  // Exclues : autre équipe, et plus de 30 jours.
  {
    id: "d3",
    team: "Data",
    content: "Demande d'une autre équipe (fictif).",
    validated_at: daysAgo(1),
  },
  {
    id: "d4",
    team: "Product",
    content: "Demande trop ancienne (fictif).",
    validated_at: daysAgo(40),
  },
];

const BLOCKER_BASE = {
  description: "Description jamais reprise dans l'idée (fictif).",
  severity: "MOYENNE",
  status: "RÉSOLU",
  created_at: daysAgo(20),
};

const BLOCKERS: Blocker[] = [
  {
    ...BLOCKER_BASE,
    id: "p1",
    title: "Accès VPN instable pour les consultants en mission chez le client (fictif)",
    teams: [],
    updated_at: daysAgo(5),
  },
  // Exclu : ne concerne que l'équipe Data.
  {
    ...BLOCKER_BASE,
    id: "p2",
    title: "Point de l'équipe Data (fictif)",
    teams: ["Data"],
    updated_at: daysAgo(3),
  },
];

const METRIC_BASE = {
  previous_value: null,
  delta: null,
  definition: null,
  impact: null,
};

const METRICS: Metric[] = [
  {
    ...METRIC_BASE,
    key: "engagement",
    label: "Engagement (fictif)",
    value: 72.5,
    unit: "%",
    trend: "hausse",
    updated_at: daysAgo(1),
  },
  {
    ...METRIC_BASE,
    key: "turnover",
    label: "Turnover (fictif)",
    value: 8.4,
    unit: "%",
    trend: "hausse",
    updated_at: daysAgo(12),
  },
];

const ALL = { requests: REQUESTS, blockers: BLOCKERS, metrics: METRICS };
const NONE = { requests: [], blockers: [], metrics: [] };

type Dismissal = { idea_key: string; reason: "masquée" | "utilisée" };

type Scenario = {
  value: string;
  label: string;
  note: string;
  data: typeof ALL | typeof NONE;
  dismissals: Dismissal[];
  /** Ouvre le rédacteur depuis l'idée de cette clé. */
  writeFrom?: string;
};

const SCENARIOS: Scenario[] = [
  {
    value: "trois",
    label: "3 idées",
    note: "La plus récente de chaque sorte : une demande de tes équipes validée, un point bloquant résolu, un KPI en hausse. Les demandes d'autres équipes et ce qui date de plus de 30 jours ne sont pas proposés.",
    data: ALL,
    dismissals: [],
  },
  {
    value: "aucune",
    label: "Aucune idée",
    note: "Rien dans les 30 derniers jours. « Partir d'un modèle » ouvre le rédacteur et la fenêtre des modèles (US25).",
    data: NONE,
    dismissals: [],
  },
  {
    value: "masquer",
    label: "Après Masquer",
    note: "Le point bloquant a été masqué : il ne revient plus. L'idée suivante (une autre demande) prend sa place. Essaie « Masquer » : « Annuler » est proposé quelques secondes.",
    data: ALL,
    dismissals: [{ idea_key: "point:p1", reason: "masquée" }],
  },
  {
    value: "rediger",
    label: "Rédiger depuis une idée",
    note: "« Rédiger » sur la demande : le brouillon reprend un titre proposé et le modèle « Rappel d'organisation ». L'extrait de la demande n'est pas repris. L'idée est marquée « utilisée » et quitte la liste.",
    data: ALL,
    dismissals: [{ idea_key: "demande:d1", reason: "utilisée" }],
    writeFrom: "demande:d1",
  },
];

/** Idée de départ du scénario « Rédiger » : calculée sans le marquage « utilisée ». */
function initialIdea(s: Scenario) {
  if (!s.writeFrom) return undefined;
  return pickNewsIdeas({ ...s.data, myTeams: KESHA.teams, dismissed: new Set() }).find(
    (i) => i.key === s.writeFrom,
  );
}

function Us26Mockup() {
  const [scenarioValue, setScenarioValue] = useState(SCENARIOS[0].value);
  const scenario = SCENARIOS.find((s) => s.value === scenarioValue) ?? SCENARIOS[0];
  const [dismissals, setDismissals] = useState<Dismissal[]>(scenario.dismissals);
  const [news, setNews] = useState<News[]>([]);
  const [composerOpen, setComposerOpen] = useState(false);
  const [mount, setMount] = useState(0);
  const composerTitle = useRef<HTMLInputElement>(null);
  const newsSection = useRef<NewsSectionHandle>(null);

  const ideas = useMemo(
    () =>
      pickNewsIdeas({
        ...scenario.data,
        myTeams: KESHA.teams,
        dismissed: new Set(dismissals.map((d) => d.idea_key)),
      }),
    [scenario, dismissals],
  );

  // Scénario « Rédiger » : le brouillon s'ouvre comme après un clic, par le vrai NewsSection.
  useEffect(() => {
    const idea = initialIdea(scenario);
    if (idea) void newsSection.current?.startDraft(ideaDraft(idea));
  }, [scenario, mount]);

  function chooseScenario(value: string) {
    const next = SCENARIOS.find((s) => s.value === value) ?? SCENARIOS[0];
    setScenarioValue(next.value);
    setDismissals(next.dismissals);
    setNews([]);
    setComposerOpen(false);
    setMount((m) => m + 1);
  }

  async function write(idea: NewsIdea) {
    if (await newsSection.current?.startDraft(ideaDraft(idea))) {
      setDismissals((list) => [...list, { idea_key: idea.key, reason: "utilisée" }]);
    }
  }

  function dismiss(idea: NewsIdea) {
    setDismissals((list) => [...list, { idea_key: idea.key, reason: "masquée" }]);
    toastUndo("Idée masquée. Elle ne te sera plus proposée.", () =>
      setDismissals((list) => list.filter((d) => d.idea_key !== idea.key)),
    );
  }

  function saveDraft(input: DraftInput, onSaved: () => void) {
    const now = new Date().toISOString();
    setNews((list) => [
      {
        id: input.id ?? `brouillon-${crypto.randomUUID()}`,
        title: input.title,
        body: input.body,
        author: KESHA.name,
        author_email: KESHA.email,
        status: "brouillon",
        created_at: now,
        updated_at: now,
        published_at: null,
        links: input.links,
        ...input.audience,
      },
      ...list.filter((n) => n.id !== input.id),
    ]);
    toast.success("Brouillon enregistré (fictif)");
    onSaved();
  }

  return (
    <div className="bg-background text-on-surface font-body-md min-h-screen flex flex-col">
      <BrandHeader>
        <OverviewHeader
          isAdmin={false}
          name={KESHA.name}
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
          <div role="status" className="min-w-0 flex-1 basis-64 space-y-xs">
            <p className="font-body-sm text-body-sm text-on-surface">
              Maquette (fictif) : {scenario.note}
            </p>
            <p className="font-body-sm text-body-sm text-on-surface-variant">
              news_idea_dismissals (fictif) :{" "}
              {dismissals.length
                ? dismissals.map((d) => `${d.idea_key} (${d.reason})`).join(", ")
                : "aucune ligne"}
            </p>
          </div>
        </div>
        <div className="flex flex-wrap items-end justify-between gap-sm">
          <div className="min-w-0 space-y-xs">
            <h1 className="font-headline-lg text-headline-lg text-primary wrap-anywhere">
              Bonjour Kesha
            </h1>
            <p className="font-body-md text-body-md text-on-surface-variant">
              Voici ce qui demande ton attention aujourd'hui.
            </p>
          </div>
          <div className="flex flex-wrap gap-xs">
            <DsButton onClick={() => toast.info("Non branché dans la maquette (fictif).")}>
              Faire une demande
            </DsButton>
            <DsButton
              variant="primary"
              icon="add"
              onClick={() => void newsSection.current?.startDraft({ title: "", body: "" })}
            >
              Publier une actu
            </DsButton>
          </div>
        </div>
        <div className="flex flex-wrap items-start gap-md">
          <div className="flex min-w-0 flex-[999_1_620px] flex-col gap-md">
            <NewsSection
              key={mount}
              editRef={newsSection}
              canWrite
              email={KESHA.email}
              news={{ data: news, isError: false, isLoading: false }}
              audienceTeams={KESHA.teams}
              audienceScope="mine"
              publishedCount={2}
              composerOpen={composerOpen}
              onComposerOpenChange={setComposerOpen}
              titleRef={composerTitle}
              saving={false}
              publishing={false}
              removing={false}
              onSave={saveDraft}
              onPublish={(input, done) => {
                toast.success("Actu publiée (fictif)");
                setNews((list) => list.filter((n) => n.id !== input.id));
                done();
              }}
              onRemove={(n) => setNews((list) => list.filter((x) => x.id !== n.id))}
              onRead={() => {}}
              ideas={
                <NewsIdeas
                  ideas={ideas}
                  onWrite={(idea) => void write(idea)}
                  onDismiss={dismiss}
                  onFromTemplate={() => void newsSection.current?.openTemplates()}
                />
              }
            />
          </div>
        </div>
      </main>
    </div>
  );
}
