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
import { emptyAudience, type NewsAudienceValue } from "@/lib/news-audience";

export const Route = createFileRoute("/_authenticated/maquettes/us08")({
  head: () => ({
    meta: [{ title: "Happy Place · Maquette du public d'une actu" }],
  }),
  component: Us08Mockup,
});

// ---------------------------------------------------------------------------
// Données factices (fictif)
// ---------------------------------------------------------------------------

type Scenario = "une" | "deux" | "aucune" | "erreur" | "confirmation" | "publiee";

const KESHA = "kesha@fictif.test";

const SCENARIOS: { value: Scenario; label: string; teams: string[]; hint: string }[] = [
  {
    value: "une",
    label: "Manager d'une équipe",
    teams: ["Product"],
    hint: "Ouvre le brouillon : rien n'est présélectionné. « Mon équipe » désigne Product, en lecture. Tu peux enregistrer le brouillon sans public.",
  },
  {
    value: "deux",
    label: "Manager de 2 équipes",
    teams: ["Marketing", "Product"],
    hint: "Ouvre le brouillon et choisis « Mon équipe » : les cases à cocher s'affichent, sans aucune case présélectionnée. Publier sans case cochée affiche un message.",
  },
  {
    value: "aucune",
    label: "Manager sans équipe",
    teams: [],
    hint: "Ouvre le brouillon : « Mon équipe » est désactivé et une phrase l'explique. Il reste « Toute l'entreprise ».",
  },
  {
    value: "erreur",
    label: "Erreur : public manquant",
    teams: ["Product"],
    hint: "Ouvre le brouillon et clique sur Publier sans choisir : rien n'est publié. Le message s'efface dès que tu choisis un public.",
  },
  {
    value: "confirmation",
    label: "Confirmation de publication",
    teams: ["Marketing", "Product"],
    hint: "Ouvre le brouillon et clique sur Publier : la confirmation reprend le public. Annule et choisis « Toute l'entreprise » pour voir l'autre phrase.",
  },
  {
    value: "publiee",
    label: "Actu publiée (puce)",
    teams: ["Marketing", "Product"],
    hint: "La puce s'affiche dans « Publiées récemment » et dans la fenêtre de lecture : ouvre une actu pour la voir.",
  },
];

const DAY_MS = 86_400_000;
const daysAgo = (days: number) => new Date(Date.now() - days * DAY_MS).toISOString();

function mockNews(
  id: string,
  days: number,
  title: string,
  status: string,
  value: NewsAudienceValue,
): News {
  const at = daysAgo(days);
  return {
    id,
    title: title && `${title} (fictif)`,
    body: "Texte de l'actu (fictif).",
    author: "Kesha (fictif)",
    author_email: KESHA,
    status,
    created_at: at,
    updated_at: at,
    published_at: status === "publiée" ? at : null,
    links: [],
    ...value,
  };
}

function newsFor(scenario: Scenario): News[] {
  const company: NewsAudienceValue = { audience: "entreprise", teams: [] };
  const published = [
    mockNews("p1", 1, "Bienvenue aux nouvelles recrues", "publiée", {
      audience: "équipe",
      teams: ["Marketing", "Product"],
    }),
    mockNews("p2", 12, "Résultats du trimestre", "publiée", company),
  ];
  if (scenario === "publiee") return published;
  const draftAudience: NewsAudienceValue =
    scenario === "confirmation"
      ? { audience: "équipe", teams: ["Marketing", "Product"] }
      : emptyAudience();
  return [mockNews("b1", 2, "Nouveau partenariat école", "brouillon", draftAudience), ...published];
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

function Us08Mockup() {
  const [scenario, setScenario] = useState<Scenario>("une");
  const [news, setNews] = useState(() => newsFor("une"));
  const [composerOpen, setComposerOpen] = useState(false);
  const [reading, setReading] = useState<News | null>(null);
  const composerTitle = useRef<HTMLInputElement>(null);

  const current = SCENARIOS.find((s) => s.value === scenario) ?? SCENARIOS[0];

  const changeScenario = (value: Scenario) => {
    setScenario(value);
    setNews(newsFor(value));
    setComposerOpen(false);
  };

  const applyDraft = (input: DraftInput, list: News[]) => {
    const fields = {
      title: input.title,
      body: input.body,
      ...input.audience,
      updated_at: daysAgo(0),
    };
    if (input.id) return list.map((n) => (n.id === input.id ? { ...n, ...fields } : n));
    const created = mockNews(crypto.randomUUID(), 0, "", "brouillon", input.audience);
    return [{ ...created, ...fields }, ...list];
  };

  const publish = (id: string, list: News[]) =>
    list.map((n) => (n.id === id ? { ...n, status: "publiée", published_at: daysAgo(0) } : n));

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
            <h1 className="font-headline-lg text-headline-lg text-primary">Bonjour Kesha</h1>
            <p className="font-body-md text-body-md text-on-surface-variant">
              Voici ce qui demande ton attention aujourd'hui.
            </p>
          </div>
          <div className="flex flex-wrap gap-xs">
            <DsButton onClick={() => toast.info("Non branché dans la maquette (fictif).")}>
              Faire une demande
            </DsButton>
            <DsButton variant="primary" icon="add" onClick={openComposer}>
              Publier une actu
            </DsButton>
          </div>
        </div>

        <TodayStrip
          canReview
          pending={[]}
          blockers={[]}
          drafts={myDrafts(news, KESHA).length}
          publishedCount={publishedThisMonth(news, KESHA)}
        />

        <div className="flex flex-wrap items-start gap-md">
          <div className="flex min-w-0 flex-[999_1_620px] flex-col gap-md">
            <ModulePlaceholder id="demandes" title="Demandes" />
            <NewsSection
              key={scenario}
              canWrite
              email={KESHA}
              news={{ data: news, isError: false, isLoading: false }}
              audienceTeams={current.teams}
              publishedCount={publishedThisMonth(news, KESHA)}
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
                setNews((list) => {
                  // Nouveau brouillon : applyDraft le place en tête de liste.
                  const next = applyDraft(input, list);
                  return publish(input.id ?? next[0].id, next);
                });
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
