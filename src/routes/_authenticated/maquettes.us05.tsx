import { createFileRoute } from "@tanstack/react-router";
import { useRef, useState } from "react";
import { flushSync } from "react-dom";
import { toast } from "sonner";
import { BrandHeader } from "@/components/brand-header";
import { DS_INPUT, DsButton, DsField, DsSection } from "@/components/ds";
import { NewsReader } from "@/components/news-reader";
import { NewsSection, type DraftInput } from "@/components/overview/NewsSection";
import { TodayStrip } from "@/components/overview/TodayStrip";
import { myDrafts, publishedThisMonth } from "@/components/overview/overview-utils";
import type { News } from "@/lib/dashboard";

export const Route = createFileRoute("/_authenticated/maquettes/us05")({
  head: () => ({
    meta: [{ title: "Happy Place · Maquette du compteur d'actus" }],
  }),
  component: Us05Mockup,
});

// ---------------------------------------------------------------------------
// Données factices (fictif)
// ---------------------------------------------------------------------------

type Scenario = "zero" | "deux" | "quatre" | "cinq" | "admin" | "collaborateur";

const KESHA = "kesha@fictif.test";
const CLAIRE = "claire@fictif.test";
const SAM = "sam@fictif.test";

const SCENARIOS: {
  value: Scenario;
  label: string;
  name: string;
  email: string;
  /** Actus publiées par le compte ce mois-ci. */
  count: number;
  hint: string;
}[] = [
  {
    value: "zero",
    label: "0 sur 4",
    name: "Kesha",
    email: KESHA,
    count: 0,
    hint: "L'actu du mois dernier et celle de Sam ne comptent pas. Publie le brouillon : le compteur passe à 1.",
  },
  {
    value: "deux",
    label: "2 sur 4",
    name: "Kesha",
    email: KESHA,
    count: 2,
    hint: "La barre est à moitié remplie, sans libellé.",
  },
  {
    value: "quatre",
    label: "4 sur 4 (cible atteinte)",
    name: "Kesha",
    email: KESHA,
    count: 4,
    hint: "La barre est pleine et « Cible atteinte » s'affiche. Publie le brouillon : rien ne t'en empêche.",
  },
  {
    value: "cinq",
    label: "5 sur 4",
    name: "Kesha",
    email: KESHA,
    count: 5,
    hint: "Le vrai nombre s'affiche, sans message d'erreur, et la barre reste pleine.",
  },
  {
    value: "admin",
    label: "Admin (compteur absent)",
    name: "Claire",
    email: CLAIRE,
    count: 2,
    hint: "Claire a publié 2 actus ce mois-ci, mais ni la section ni la tuile ne l'indiquent. Le reste ne change pas.",
  },
  {
    value: "collaborateur",
    label: "Collaborateur (compteur absent)",
    name: "Thomas",
    email: "thomas@fictif.test",
    count: 0,
    hint: "Ni compteur, ni rédacteur, ni tuile de brouillons : il ne reste que les actus publiées.",
  },
];

const MINUTE_MS = 60_000;
const DAY_MS = 86_400_000;
const ago = (ms: number) => new Date(Date.now() - ms).toISOString();

function draft(id: string, email: string, at: string, title: string): News {
  return {
    id,
    title: title && `${title} (fictif)`,
    body: "Texte de l'actu (fictif).",
    author: `${email.split("@")[0]} (fictif)`,
    author_email: email,
    status: "brouillon",
    created_at: at,
    updated_at: at,
    links: [],
  };
}

function published(id: string, email: string, at: string, title: string): News {
  return { ...draft(id, email, at, title), status: "publiée", published_at: at };
}

const TITLES = [
  "Bienvenue aux nouvelles recrues",
  "Nouveau partenariat école",
  "Retour sur le séminaire d'automne",
  "Nouvelle offre cadre IT",
  "Point mensuel",
];

// (fictif) À quelques minutes d'écart, pour rester dans le mois en cours même le 1er.
function newsFor(scenario: Scenario): News[] {
  const { email, count } = SCENARIOS.find((s) => s.value === scenario) ?? SCENARIOS[0];
  const mine = TITLES.slice(0, count).map((title, i) =>
    published(`p${i}`, email, ago((i + 1) * MINUTE_MS), title),
  );
  return [
    draft("b1", KESHA, ago(5 * DAY_MS), "Calendrier des congés"),
    ...mine,
    published("h1", SAM, ago(10 * MINUTE_MS), "Actu de Sam, ce mois-ci"),
    published("h2", email, ago(40 * DAY_MS), "Actu du mois dernier"),
  ];
}

// ---------------------------------------------------------------------------
// Présentation
// ---------------------------------------------------------------------------

function ModulePlaceholder({ id, title }: { id: string; title: string }) {
  return (
    <DsSection id={id} title={title} className="bg-surface-container">
      <p className="font-body-sm text-body-sm text-on-surface-variant">
        Module existant, non modifié (fictif).
      </p>
    </DsSection>
  );
}

function Us05Mockup() {
  const [scenario, setScenario] = useState<Scenario>("deux");
  const [news, setNews] = useState(() => newsFor("deux"));
  const [composerOpen, setComposerOpen] = useState(false);
  const [reading, setReading] = useState<News | null>(null);
  const composerTitle = useRef<HTMLInputElement>(null);

  const current = SCENARIOS.find((s) => s.value === scenario) ?? SCENARIOS[0];
  const canWrite = scenario !== "collaborateur";
  const isManager = canWrite && scenario !== "admin";
  const publishedCount = isManager ? publishedThisMonth(news, current.email) : undefined;

  const changeScenario = (value: Scenario) => {
    setScenario(value);
    setNews(newsFor(value));
    setComposerOpen(false);
  };

  const applyDraft = (input: DraftInput, list: News[]) => {
    const fields = { title: input.title, body: input.body, updated_at: ago(0) };
    if (input.id) return list.map((n) => (n.id === input.id ? { ...n, ...fields } : n));
    const created = draft(crypto.randomUUID(), current.email, ago(0), "");
    return [{ ...created, ...fields }, ...list];
  };

  const publish = (id: string, list: News[]) =>
    list.map((n) => (n.id === id ? { ...n, status: "publiée", published_at: ago(0) } : n));

  const openComposer = () => {
    flushSync(() => setComposerOpen(true));
    composerTitle.current?.focus();
  };

  return (
    <div className="bg-background text-on-surface font-body-md min-h-screen flex flex-col">
      <BrandHeader>
        <span className="font-label-md text-label-md normal-case tracking-normal text-on-surface-variant">
          Happy Place
        </span>
      </BrandHeader>
      <main className="flex-grow w-full max-w-interface mx-auto p-sm md:p-md space-y-md">
        <div className="flex flex-wrap items-end gap-sm border border-dashed border-outline-variant p-sm">
          <DsField id="maquette-etat" label="Maquette (fictif)" className="w-full md:w-72">
            <select
              id="maquette-etat"
              className={DS_INPUT}
              value={scenario}
              onChange={(e) => changeScenario(e.target.value as Scenario)}
            >
              {SCENARIOS.map((s) => (
                <option key={s.value} value={s.value}>
                  {s.label}
                </option>
              ))}
            </select>
          </DsField>
          <p className="min-w-0 flex-1 basis-64 font-body-sm text-body-sm text-on-surface-variant">
            {current.hint}
          </p>
        </div>

        <div className="flex flex-wrap items-end justify-between gap-sm">
          <div className="min-w-0 space-y-xs">
            <h1 className="font-headline-lg text-headline-lg text-primary">
              Bonjour {current.name}
            </h1>
            <p className="font-body-md text-body-md text-on-surface-variant">
              Voici ce qui demande ton attention aujourd'hui.
            </p>
          </div>
          <div className="flex flex-wrap gap-xs">
            <DsButton
              variant={canWrite ? "secondary" : "primary"}
              onClick={() => toast.info("Non branché dans la maquette (fictif).")}
            >
              Faire une demande
            </DsButton>
            {canWrite && (
              <DsButton variant="primary" icon="add" onClick={openComposer}>
                Publier une actu
              </DsButton>
            )}
          </div>
        </div>

        <TodayStrip
          canReview={canWrite}
          pending={[]}
          blockers={[]}
          drafts={myDrafts(news, current.email).length}
          publishedCount={publishedCount}
        />

        <div className="flex flex-wrap items-start gap-md">
          <div className="flex min-w-0 flex-[999_1_620px] flex-col gap-md">
            <ModulePlaceholder id="demandes" title="Demandes" />
            <NewsSection
              key={scenario}
              canWrite={canWrite}
              email={current.email}
              news={{ data: news, isError: false, isLoading: false }}
              publishedCount={publishedCount}
              composerOpen={composerOpen}
              onComposerOpenChange={setComposerOpen}
              titleRef={composerTitle}
              saving={false}
              publishing={false}
              removing={false}
              onSave={(input, onSaved) => {
                setNews((list) => applyDraft(input, list));
                toast.success("Brouillon enregistré (fictif)");
                onSaved();
              }}
              onPublish={(input, onPublished) => {
                setNews((list) => publish(input.id, applyDraft(input, list)));
                toast.success("Actualité publiée (fictif)");
                onPublished();
              }}
              onRemove={(n) => {
                setNews((list) => list.filter((item) => item.id !== n.id));
                toast.success("Brouillon supprimé (fictif)");
              }}
              onRead={setReading}
            />
          </div>
          <div className="flex min-w-0 flex-[1_1_380px] flex-col gap-md">
            <ModulePlaceholder id="blocages" title="Points bloquants" />
            <ModulePlaceholder id="indicateurs" title="Indicateurs" />
          </div>
        </div>
      </main>
      <NewsReader news={reading} onClose={() => setReading(null)} />
    </div>
  );
}
